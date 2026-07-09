#!/usr/bin/env bash

# Check for required commands
command -v find > /dev/null || {
  echo "find required"
  exit 1
}
command -v sort > /dev/null || {
  echo "sort required"
  exit 1
}
command -v mkdir > /dev/null || {
  echo "mkdir required"
  exit 1
}

# Set script to fail on errors and unset variables
set -euo pipefail

# Directory containing the backup files
backup_dir="."
upload_dir="upload"

# Create upload directory if it doesn't exist
mkdir -p "$upload_dir"
echo "Created upload directory: $upload_dir"

declare -A newest_file newest_time

# Find all backup files and process each one
find "$backup_dir" -name "backup_*.tgz" -printf "%T+ %p\0" \
  | while IFS= read -r -d '' time file; do
    # Extract the firewall name from the filename
    firewall_name=$(basename "$file" | cut -d'-' -f2)
    echo "Processing file: $file"

    # Convert modification time to epoch for comparison
    mtime=$(date -d "$time" +%s)

    if [[ -z "${newest_time[$firewall_name]+x}" ]] || ((mtime > newest_time[$firewall_name])); then
      # This file is newer than the current "newest" for this firewall.
      # If there was a previous newest, it's no longer the newest -> move it out.
      if [[ -n "${newest_file[$firewall_name]+x}" ]]; then
        echo "Moving previous newest file for $firewall_name to upload directory: ${newest_file[$firewall_name]}"
        mv "${newest_file[$firewall_name]}" "$upload_dir/"
      fi
      newest_file[$firewall_name]="$file"
      newest_time[$firewall_name]=$mtime
    else
      # Not the newest for this firewall -> move to upload directory
      echo "Moving file to upload directory: $file"
      mv "$file" "$upload_dir/"
    fi
  done

echo "All files processed. Newest files retained in current directory, others moved to upload directory."
