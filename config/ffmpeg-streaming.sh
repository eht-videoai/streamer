#!/bin/bash

# This script is used in a Docker container to stream RTSP feeds with conditional encoding.

echo "🎬 Starting RTSP streams with conditional H264/AAC encoding..."

# Install inotify-tools if not already installed
if ! command -v inotifywait &> /dev/null; then
  echo "📦 Installing inotify-tools..."
  apt-get update -qq && apt-get install -y -qq inotify-tools
fi

# Function to check the video codec
check_codec() {
  local file=$1
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$file"
}

# Function to start a stream with conditional encoding
start_stream() {
  local input_file=$1
  local output_url=$2

  # Vérifie le codec vidéo
  codec=$(check_codec "$input_file")

  if [[ "$codec" == "h264" || "$codec" == "hevc" ]]; then
    echo "✅ $input_file is already in $codec, starting without re-encoding."
    ffmpeg -re -stream_loop -1 -i "$input_file" -c copy -f rtsp "$output_url" &>/dev/null &
  else
    echo "♻️ $input_file is not in H264/H265, re-encoding in progress..."
    ffmpeg -re -stream_loop -1 -i "$input_file" \
      -vcodec libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
      -x264opts "keyint=30:min-keyint=30:no-scenecut" \
      -b:v 2M -maxrate 2M -bufsize 4M \
      -acodec aac -ar 44100 -b:a 128k -f rtsp "$output_url" &>/dev/null &
  fi

  # Log du chemin d'accès au flux
  echo "🎥 Streaming \"$(basename "$input_file")\" to \"$output_url\""
}

# Function to watch for new files
watch_directory() {
  local video_dir=$1
  local base_url="rtsp://localhost"

  echo "👀 Watching directory $video_dir for new files..."

  inotifywait -m -e create --format "%f" "$video_dir" | while read -r new_file; do
    if [[ "$new_file" == *.mp4 ]]; then
      local input_file="$video_dir/$new_file"
      local stream_name=$(basename "$new_file" .mp4)
      local output_url="$base_url/$stream_name"

      echo "📂 New file detected: $input_file"
      start_stream "$input_file" "$output_url"
    fi
  done
}

# Initial startup of streams for existing files
video_dir="/videos"
base_url="rtsp://localhost"

for video_file in "$video_dir"/*.mp4; do
  if [[ -f "$video_file" ]]; then
    stream_name=$(basename "$video_file" .mp4)
    output_url="$base_url/$stream_name"
    start_stream "$video_file" "$output_url"
  fi
done

echo "✅ All existing streams are running."

# Start the watcher to detect new files
watch_directory "$video_dir" &
wait