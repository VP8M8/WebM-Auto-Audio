#!/bin/bash
# v1.0.1 2016-11-25 VP8M8
# Description: Increases/decreases the audio bitrate of WebMs in steps to satisfy the target file size
# Note: All files are handled in MiB (based on 2^10, not 10^3) and the target file size must be in MiB
# Depenencies: ffmpeg, ffprobe, bc, sed, grep, cut
# Usage: script.sh ["source video" or "source audio"] ["webm video"] [webm audio bitrate] [target file size]

# Check for dependencies
for depencency in ffmpeg ffprobe bc sed grep cut; do
	if [[ $(command -v $depencency >/dev/null 2>&1) -ne 0 ]]; then
		echo "This script requires \"$depencency\" but it's not installed."
		echo "Install it."
		exit 1
	fi
done

# Displays help if first argument is -h or --help
if [[ "$1" = "-h" || "$1" = "--help" ]]; then
	echo "Usage: "$0" [\"source video\" or \"source audio\"] [\"webm video\"] [webm audio bitrate] [target file size]"
	echo "Example: "$0" \"original video.mkv\" \"encoded video.webm\" 64k 12M"
	exit 0
fi

source_video="$1"
webm_video="$2"
audio_bitrate="$3"
target_filesize="$4"

# Set default values
overshoot_percent=104
undershoot_percent=92
bitrate_step=4

# In case the user puts 'M' or 'MB' after the target file size it is discarded
# I do the same thing later on for the audio bitrate in case there is a 'k' at the end
target_filesize=$(echo "$target_filesize" | sed 's/M$//')
target_filesize=$(echo "$target_filesize" | sed 's/MB$//')
overshoot_filesize=$(echo "scale=3;$target_filesize*($overshoot_percent)/100" | bc)
undershoot_filesize=$(echo "scale=3;$target_filesize*($undershoot_percent)/100" | bc)
times_increased=0
times_decreased=0
webm_filesize_bytes=$(ffprobe "$webm_video" -loglevel quiet -show_format | grep size | cut -f2 -d=)
webm_filesize=$(echo "scale=8;$webm_filesize_bytes/1024/1024" | bc)
file_ratio=$(echo "scale=8;$webm_filesize/$target_filesize*100" | bc)

# If webm file size is equal to target file size
if [[ $(echo "$file_ratio == 100" | bc) -eq 1 ]]; then
	echo "The webm is exactly the target file size."
	echo "There is no more work to be done."
	exit 0
fi

# If webm file size is over/under the overshoot/undershoot percent
if [[ $(echo "$file_ratio > $overshoot_percent" | bc) -eq 1 || $(echo "$file_ratio < $undershoot_percent" | bc) -eq 1 ]]; then
	echo "The webm file size is $(echo "$webm_filesize" | sed 's/.\{5\}$//')MB which is $(echo "$file_ratio" | sed 's/.\{5\}$//')% of the target size of "$target_filesize"MB."
	echo "The webm should be within "$overshoot_percent"%-"$undershoot_percent"% of the target size."
	echo "This means it should be within "$overshoot_filesize"MB-"$undershoot_filesize"MB to be used."
	echo "Consider re-encoding with larger/smaller video bitrate for optimal quality."
	exit 1
fi

# Increases the audio bitrate until the webm is slightly over the target file size
while [[ $(echo "$file_ratio < 100" | bc) -eq 1 && $(echo "$file_ratio >= $undershoot_percent" | bc) -eq 1 ]]; do
	echo "The webm was too small so the audio bitrate is being increased..."
	audio_bitrate_raw=$(echo "$audio_bitrate" | sed 's/k$//')
	audio_bitrate_raw=$(echo "$audio_bitrate_raw+$bitrate_step" | bc)
	audio_bitrate=$(echo "$audio_bitrate_raw" | sed 's/$/k/')
	((times_increased++))
	ffmpeg -i "$source_video" -i "$webm_video" -map 1:v:0 -map 0:a:0 -loglevel quiet -c:v copy -c:a libopus -b:a "$audio_bitrate" "$webm_video"-increased#"$times_increased".webm
	rm "$webm_video"
	mv "$webm_video"-increased#"$times_increased".webm "$webm_video"
	echo "Checking if more passes are needed..."
	webm_filesize_bytes=$(ffprobe "$webm_video" -loglevel quiet -show_format | grep size | cut -f2 -d=)
	webm_filesize=$(echo "scale=8;$webm_filesize_bytes/1024/1024" | bc)
	file_ratio=$(echo "scale=8;$webm_filesize/$target_filesize*100" | bc)
done

# Very rare case that the file size is initially increased above the overshoot percent threshold
if [[ $(echo "$file_ratio >= $overshoot_percent" | bc) -eq 1 ]]; then
	echo "*** Warning! The webm is over the overshoot percent threshold! ***"
	echo "Reverting all changes..."
	overshoot_percent=1000
fi

# Decreases the audio bitrate until the webm is slightly under the target file size
while [[ $(echo "$file_ratio > 100" | bc) -eq 1 && $(echo "$file_ratio <= $overshoot_percent" | bc) -eq 1 ]]; do
	echo "The webm was too big so the audio bitrate is being decreased..."
	audio_bitrate_raw=$(echo "$audio_bitrate" | sed 's/k$//')
	audio_bitrate_raw=$(echo "$audio_bitrate_raw-$bitrate_step" | bc)
	audio_bitrate=$(echo "$audio_bitrate_raw" | sed 's/$/k/')
	((times_decreased++))
	ffmpeg -i "$source_video" -i "$webm_video" -map 1:v:0 -map 0:a:0 -loglevel quiet -c:v copy -c:a libopus -b:a "$audio_bitrate" "$webm_video"-decreased#"$times_decreased".webm
	rm "$webm_video"
	mv "$webm_video"-decreased#"$times_decreased".webm "$webm_video"
	if [[ $overshoot_percent = "1000" ]]; then
		echo "Try again with a lower bitrate step."
		exit 1
	fi
	echo "Checking if more passes are needed..."
	webm_filesize_bytes=$(ffprobe "$webm_video" -loglevel quiet -show_format | grep size | cut -f2 -d=)
	webm_filesize=$(echo "scale=8;$webm_filesize_bytes/1024/1024" | bc)
	file_ratio=$(echo "scale=8;$webm_filesize/$target_filesize*100" | bc)
done

webm_filesize=$(echo "$webm_filesize" | sed 's/.\{5\}$//')
file_ratio=$(echo "scale=3;$webm_filesize/$target_filesize*100" | bc)
audio_bitrate_raw=$(echo "$audio_bitrate" | sed 's/k$//')
original_bitrate_raw=$(echo "$3" | sed 's/k$//')

echo "Finished! The webm should now be very close to the target file size."
echo "[============ Stats ============]"
echo "The webm file size is "$webm_filesize"MB which is "$file_ratio"% of the target size of "$target_filesize"MB."
echo "The audio bitrate was increased "$times_increased" times and decreased "$times_decreased" times."
echo "The initial audio bitrate was "$3" and the final bitrate is "$audio_bitrate","
echo "which is a difference of $(echo "scale=3;$audio_bitrate_raw-$original_bitrate_raw" | bc)k."
exit 0
