#!/bin/bash

#==============================================================================
# CONFIGURATION SECTION - Edit these values
#==============================================================================

# LOCAL SETTINGS
SOURCE_DIR="."          # Current directory where backup .tgz files are located
ARCHIVE_DIR="./archive" # Local folder where old backups will be stored (default: ./archive)

# FTP/SCP SERVER SETTINGS
SERVER_HOST="your-server.com"  # Your SFTP server hostname or IP address
SERVER_PORT="22"               # SSH port (usually 22 for SFTP)
REMOTE_USER="ftp_user_name"    # Username for the remote server
REMOTE_PATH="/remote/backups/" # Full path on remote server where files will be uploaded

# AUTHENTICATION
SSH_KEY_FILE="${HOME}/.ssh/id_rsa" # Path to your private SSH key (e.g., id_rsa, id_ed25519)
SSH_KEY_PASS=""                    # If you have a password-protected key, enter it here (empty if no passphrase)

#==============================================================================
# END CONFIGURATION - DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING
#==============================================================================

# Check if SSH Key File exists
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "ERROR: SSH Key file not found at: $SSH_KEY_FILE"
  echo "Please set the SSH_KEY_FILE path correctly or generate an SSH key."
  exit 1
fi

# Create local archive directory if it doesn't exist
mkdir -p "$ARCHIVE_DIR"

echo "=========================================="
echo "BACKUP CLEANUP & UPLOAD SCRIPT"
echo "=========================================="

declare -A keep_files
declare -A latest_times

echo ""
echo "--- STEP 1: Analyzing files to keep (Newest per firewall) ---"

# Loop through all matching files using find with null-terminated output for safety
while IFS= read -r -d '' file; do
  # Extract the Firewall ID from the filename pattern
  # Regex captures the first group of non-dash characters after "backup_-"
  id=$(basename "$file" | sed 's/.*\(backup_\)-\([^_-]*\)-.*/\2/')

  # Get file modification time in seconds (epoch) - handles Linux and macOS
  if [[ $(uname) == *"Darwin"* ]]; then
    mtime=$(stat -f %m "$file")
  else
    mtime=$(stat -c %Y "$file")
  fi

  # Determine if this is the newest for this ID
  if [[ ! -v keep_files["$id"] ]]; then
    keep_files["$id"]="$file"
    latest_times["$id"]="$mtime"
  else
    existing_time="${latest_times[$id]}"
    if [[ "$mtime" -gt "$existing_time" ]]; then
      keep_files["$id"]="$file"
      latest_times["$id"]="$mtime"
    fi
  fi
done < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.tgz" -print0)

echo ""
echo "--- STEP 2: Moving older backups to Archive ---"

# Iterate all found files and move if not marked for keep
for file in $(find "$SOURCE_DIR" -maxdepth 1 -name "*.tgz"); do
  id=$(basename "$file" | sed 's/.*\(backup_\)-\([^_-]*\)-.*/\2/')

  # If this file is NOT the newest (not in keep_files or not equal to kept file)
  if [[ "${keep_files[$id]}" != "$file" ]]; then
    echo "Moving:   $file -> $ARCHIVE_DIR/"
    mv "$file" "$ARCHIVE_DIR/" 2> /dev/null || echo "WARNING: Could not move $file"
  else
    echo "Keeping:   $file"
  fi
done

echo ""
echo "--- STEP 3: Uploading Archive to FTP/SFTP Server ---"

# Check if archive folder has files to upload
archived_files=$(find "$ARCHIVE_DIR" -name "*.tgz" -print0 | wc -c)
if [[ $archived_files -eq 1 ]]; then # If count is 1 (empty), no .tgz files found
  echo "No backup files found in $ARCHIVE_DIR to upload."
  exit 0
fi

# Function to upload files using scp
upload_to_server() {
  local file="$1"
  local basename="${file##*/}" # Get just filename

  echo "Uploading: $basename to $SERVER_HOST:$REMOTE_PATH"

  if [[ -n "$SSH_KEY_PASS" ]]; then
    # Use ssh-agent with password for key (if key is encrypted)
    scp -i "$SSH_KEY_FILE" -P "$SERVER_PORT" -o StrictHostKeyChecking=no "$file" "root@$SERVER_HOST$REMOTE_PATH$basename" 2>&1
  else
    # Standard SCP with SSH key
    scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -P "$SERVER_PORT" "$file" "root@$SERVER_HOST$REMOTE_PATH$basename" 2>&1
  fi

  if [[ $? -eq 0 ]]; then
    echo "Upload Successful."
  else
    echo "ERROR: Upload Failed for $file"
  fi
}

# Loop through archived files and upload them
for file in $(find "$ARCHIVE_DIR" -name "*.tgz"); do
  # Ensure the file exists and is readable
  if [[ -f "$file" ]]; then
    upload_to_server "$file"
  else
    echo "Skipping: $file (File does not exist)"
  fi
done

echo ""
echo "=========================================="
echo "PROCESSING COMPLETE"
echo "=========================================="
