#!/usr/bin/env bash

# Check for required commands
command -v find > /dev/null || {
  echo "find required"
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

echo "==> Starting backup sort in '$backup_dir', older files go to '$upload_dir/'"

# Create upload directory if it doesn't exist
mkdir -p "$upload_dir"

# Track the newest file seen so far for each system, keyed by firewall/system name
declare -A newest_file
declare -A newest_time

file_count=0
moved_count=0

# Find all backup files and process them in a single pass, keeping only the
# newest file per system in "$backup_dir" and moving all older ones to upload.
while IFS= read -r -d '' file; do
  base=$(basename "$file")
  # Extract the system name from the filename (backup-<system_name>-fqdn-date.tgz)
  firewall_name=$(echo "$base" | cut -d'-' -f2)
  mtime=$(stat -c %Y "$file")

  file_count=$((file_count + 1))
  echo "[$file_count] Checking '$base' (system: $firewall_name, modified: $(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S'))"

  if [[ -z "${newest_time[$firewall_name]+x}" ]] || ((mtime > newest_time[$firewall_name])); then
    # This file is newer than the current "newest" for this system.
    # If there was a previous newest, it's no longer the newest -> move it out.
    if [[ -n "${newest_file[$firewall_name]+x}" ]]; then
      old_base=$(basename "${newest_file[$firewall_name]}")
      echo "    -> '$base' is newer than previous newest '$old_base' for '$firewall_name'"
      echo "    -> moving superseded file '$old_base' to '$upload_dir/'"
      mv "${newest_file[$firewall_name]}" "$upload_dir/"
      moved_count=$((moved_count + 1))
    else
      echo "    -> first file seen for system '$firewall_name', keeping in place for now"
    fi
    newest_file[$firewall_name]="$file"
    newest_time[$firewall_name]=$mtime
  else
    echo "    -> older than current newest for '$firewall_name', moving to '$upload_dir/'"
    mv "$file" "$upload_dir/"
    moved_count=$((moved_count + 1))
  fi
done < <(find "$backup_dir" -maxdepth 1 -name "backup-*.tgz" -print0)

echo "==> Done. Processed $file_count file(s), moved $moved_count to '$upload_dir/'."
if ((${#newest_file[@]} > 0)); then
  echo "==> Newest backup kept in '$backup_dir' for each system:"
  for name in "${!newest_file[@]}"; do
    echo "    - $name: $(basename "${newest_file[$name]}")"
  done
else
  echo "==> No matching backup files found."
fi
