#!/bin/bash
# Turns an iPad screen recording into an App Store app preview:
# 1600 x 1200 (13-inch iPad, landscape), 30 fps, H.264, stereo AAC 256 kbps
# at 48 kHz (a silent track if the recording has no sound), 15-30 seconds.
#
#   tools/app-store/preview.sh <recording> <start> <end> [name]
#   tools/app-store/preview.sh ~/Desktop/figma.mov 3.5 25 figma
#
# start and end are seconds (or hh:mm:ss.s) into the recording. Writes
# store/out/preview-<name>.mp4. Needs ffmpeg (brew install ffmpeg).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[ $# -ge 3 ] || { sed -n 2,11p "$0"; exit 1; }
input=$1 start=$2 end=$3 name=${4:-$(basename "${1%.*}")}
out=store/out/preview-$name.mp4
mkdir -p store/out

seconds() { awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }' <<<"$1"; }
length=$(awk -v a="$(seconds "$start")" -v b="$(seconds "$end")" 'BEGIN { print b - a }')
awk -v l="$length" 'BEGIN { exit !(l >= 15 && l <= 30) }' \
    || { echo "The preview is $length s; the App Store takes 15 to 30 s."; exit 1; }

# A recording made in portrait is turned to landscape first.
w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")
h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")
rotate=""
[ "$w" -lt "$h" ] && rotate="transpose=${TRANSPOSE:-2},"
# Scale to fit 1600 x 1200 and pad any difference in shape with black.
video="${rotate}scale=1600:1200:force_original_aspect_ratio=decrease,pad=1600:1200:(ow-iw)/2:(oh-ih)/2:black,fps=30,format=yuv420p"

silence=()
sound=0:a:0
if [ -z "$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$input")" ]; then
    silence=(-f lavfi -t "$length" -i anullsrc=channel_layout=stereo:sample_rate=48000)
    sound=1:a
fi

ffmpeg -v error -y -ss "$start" -to "$end" -i "$input" ${silence[@]+"${silence[@]}"} \
    -map 0:v:0 -map "$sound" -vf "$video" \
    -c:v libx264 -profile:v high -preset slow -crf 18 -r 30 \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "$out"

ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,channels,sample_rate \
    -show_entries format=duration -of compact=p=0:nk=0 "$out"
echo "$out"
