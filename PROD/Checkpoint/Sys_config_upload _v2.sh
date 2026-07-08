#!/bin/bash

# Enable strict error handling
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
TARGET_DIR="${SCRIPT_DIR}/upload"

# Create the upload directory if it doesn't exist
mkdir -p "${TARGET_DIR}"

echo "Scanning for firewall backup files..."

# Associative arrays to track the newest file for each firewall ID
declare -A best_time
declare -A best_file

# Loop through all .tgz files in the current directory (depth 1 only)
# We use 'find' with stat (-printf '%T@') to get the epoch timestamp.
# Note: On most Linux filesystems, %T@ (mtime) is used as the standard reference
# for file age because true "creation time" is not universally readable via POSIX tools.
# This respects the instruction to NOT parse the date from the filename.

while IFS= read -r line; do
  # Parse timestamp and filename from find output format: "EPOCH FILENAME"
  epoch=$(echo "$line" | awk '{print $1}')
  file="$line" # Keep as is for later, remove quotes if needed

  # Extract the Firewall ID
  # Pattern in your filenames: backup_-<ID>_<ID>.domain...
  # Regex removes "backup_-" prefix and everything starting from "-" to the end
  id=$(basename "$file" | sed 's/^backup_-//; s/-.*$//')

  # Check if we haven't seen this ID before, or if this file is newer
  if [[ -z "${best_time[$id]}" ]] || ((epoch > best_time[$id])); then
    best_time[$id]=$epoch
    best_file[$id]=$file
  fi
done < <(find . -maxdepth 1 -name '*.tgz' -printf '%T@ %f\n')

# Identify which files are NOT the newest and move them to upload
echo "Rotating backups..."
for file in $(find . -maxdepth 1 -name '*.tgz'); do
  # Extract ID for this specific file again (in case of spaces or path issues)
  current_id=$(basename "$file" | sed 's/^backup_-//; s/-.*$//')

  # Check if this file is NOT the one marked as "best" (newest) for its group
  if [[ "${best_file[$current_id]}" != *"$file"* ]]; then
    mv -n -- "$file" "${TARGET_DIR}/"
    echo "Moved: $file -> ${TARGET_DIR}/"
  fi
done

echo ""
echo "Process finished. Keep files in current directory:"
ls -lh ./*.tgz 2> /dev/null || echo "(No backup files remaining in root)"
echo ""
echo "Older backups moved to upload folder:"
ls -lha ${TARGET_DIR}/ | head -n 10 || echo "(Empty or no older backups found)"
