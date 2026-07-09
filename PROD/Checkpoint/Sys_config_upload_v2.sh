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

# Find all backup files, sort them by modification time, and process each group of backups for a firewall
find "$backup_dir" -name "backup_*.tgz" -print0 \
  | while IFS= read -r -d '' file; do
    # Extract the firewall name from the filename
    firewall_name=$(basename "$file" | cut -d'-' -f2)

    # Find the newest backup for this firewall and move it to upload directory
    newest_file=$(find "$backup_dir" -name "backup_${firewall_name}*.tgz" -newermt "$(stat -c %Y "$file")" 2> /dev/null || true)
    if [[ -n "$newest_file" ]]; then
      mv "$newest_file" "$upload_dir"
    fi

    # Move the current file to upload directory
    mv "$file" "$upload_dir"
  done
