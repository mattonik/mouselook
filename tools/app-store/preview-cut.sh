#!/bin/bash
# Cuts a screen recording into segments and joins them with straight cuts.
#
#   tools/app-store/preview-cut.sh <recording> <name> <from-to>...
#   tools/app-store/preview-cut.sh rec.mp4 figma 0.5-3.3 10.3-12.8 72.3-78.3
#
# By default it makes an App Store preview: store/out/preview-<name>.mp4,
# 1600 x 1200, 30 fps, H.264, a silent stereo AAC track (the App Store needs
# one), 15-30 s in total. WEB=1 makes a website video instead:
# store/out/web/<name>.mp4, 1280 x 960, no sound, any length, plus a poster
# frame (<name>.jpg) from POSTER seconds into the result (default 5).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

[ $# -ge 3 ] || { sed -n 2,11p "$0"; exit 1; }
input=$1 name=$2
shift 2

filters="" labels="" total=0 n=0
for segment in "$@"; do
    from=${segment%-*} to=${segment#*-}
    filters+="[0:v]trim=start=$from:end=$to,setpts=PTS-STARTPTS[s$n];"
    labels+="[s$n]"
    total=$(awk -v t="$total" -v a="$from" -v b="$to" 'BEGIN { print t + b - a }')
    n=$((n + 1))
done

# A portrait recording is turned to landscape first.
w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")
h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")
rotate=""
[ "$w" -lt "$h" ] && rotate="transpose=${TRANSPOSE:-2},"

if [ "${WEB:-0}" = 1 ]; then
    size=1280:960 out=store/out/web/$name.mp4
    mkdir -p store/out/web
else
    awk -v l="$total" 'BEGIN { exit !(l >= 15 && l <= 30) }' \
        || { echo "The segments add up to $total s; an App Store preview takes 15 to 30 s."; exit 1; }
    size=1600:1200 out=store/out/preview-$name.mp4
    mkdir -p store/out
fi
video="${labels}concat=n=$n:v=1:a=0,${rotate}scale=$size:force_original_aspect_ratio=decrease,"
video+="pad=$size:(ow-iw)/2:(oh-ih)/2:black,fps=30,format=yuv420p[v]"

if [ "${WEB:-0}" = 1 ]; then
    ffmpeg -v error -y -i "$input" -filter_complex "$filters$video" -map "[v]" -an \
        -c:v libx264 -profile:v high -preset slow -crf 24 -movflags +faststart "$out"
    ffmpeg -v error -y -ss "${POSTER:-5}" -i "$out" -frames:v 1 -q:v 4 "${out%.mp4}.jpg"
else
    ffmpeg -v error -y -i "$input" -f lavfi -t "$total" -i anullsrc=channel_layout=stereo:sample_rate=48000 \
        -filter_complex "$filters$video" -map "[v]" -map 1:a \
        -c:v libx264 -profile:v high -preset slow -crf 18 -r 30 \
        -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "$out"
fi

ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate \
    -show_entries format=duration -of compact=p=0:nk=0 "$out"
echo "$out ($n segments, $total s)"
