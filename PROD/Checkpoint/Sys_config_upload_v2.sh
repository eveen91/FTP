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

# SFTP connection parameters
ssh_key="/path/to/your/private/key"
sftp_user="sftp_username"
sftp_server="sftp.server.com"
remote_dir="/remote/directory/"

echo "==> Starting backup sort in '$backup_dir', older files go to '$upload_dir/'"

# Create upload directory if it doesn't exist
mkdir -p "$upload_dir"

# Track the newest file seen so far for each system, keyed by firewall/system name
declare -A newest_file
declare -A newest_time

file_count=0
moved_count=0

# Use a temp file instead of process substitution (avoids relying on /dev/fd,
# which isn't available in some restricted/minimal environments)
file_list=$(mktemp)
trap 'rm -f "$file_list"' EXIT

find "$backup_dir" -maxdepth 1 -name "backup_-*.tgz" -print0 > "$file_list"

while IFS= read -r -d '' file; do
  base=$(basename "$file")
  # Extract the system name from the filename (backup_-<system_name>-fqdn-date.tgz)
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
done < "$file_list"

echo "==> Done. Processed $file_count file(s), moved $moved_count to '$upload_dir/'."
if ((file_count > 0)); then
  echo "==> Uploading files in '$upload_dir' to the SFTP server."

  for file in "$upload_dir"/*; do
    if [[ -f "$file" ]]; then
      scp -i "$ssh_key" "$file" "$sftp_user@$sftp_server:$remote_dir/"
      echo "Uploaded $file"
    fi
  done

  # Function to check if files exist on the SFTP server
  function check_files_on_sftp {
    local sftp_command="sftp -i '$ssh_key' '$sftp_user@$sftp_server'"
    for file in "$upload_dir"/*; do
      if [[ -f "$file" ]]; then
        base=$(basename "$file")
        remote_file="$remote_dir/$base"
        # Check if the file exists on the SFTP server
        if ssh -i "$ssh_key" "$sftp_user@$sftp_server" test -e "$remote_file"; then
          echo "File '$base' exists on the SFTP server."
        else
          echo "File '$base' does not exist on the SFTP server."
        fi
      fi
    done
  }

  check_files_on_sftp

  echo "==> Uploaded all files to the SFTP server and verified existence."
else
  echo "==> No matching backup files found or no files were moved for upload."
fi
