#!/bin/bash

# ==========================================
# SCP Connection Settings + REMOVAL AFTER VERIFICATION
# ==========================================
SSH_HOST="your.appliance.com" # Host IP or name
SSH_USER="user_appliance"     # User on the server
REMOTE_DIR="/path/to/files/"  # Target path on the server

SSH_KEY="/home/admin/.ssh/id_ed25519" # Path to SSH key (ed25519)

LOG_FILE="/tmp/CPSnapshot_cleanup.log"
UPLOAD_FOLDER="./upload"

set -euo pipefail

mkdir -p "$UPLOAD_FOLDER" 2> /dev/null || {
  echo "Cannot create folder $UPLOAD_FOLDER"
  exit 1
}
mkdir -p "$(dirname "$LOG_FILE")"

log_msg() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

log_msg "Starting cleanup and SCP file transfer process..."

# ==========================================
# PART 0: CHECK UPLOAD FOLDER (LOGIC CORRECTION)
# ==========================================

all_files=(*.tar)
shopt -s nullglob

if [ ${#all_files[@]} -eq 0 ]; then
  log_msg "Error: No .tar files found in the catalog"
  exit 1
fi

log_msg "Checking contents of folder '$UPLOAD_FOLDER'..."

files_to_upload=()

# If upload folder is not empty, add existing files to the upload list
if [ -n "$(ls -A "$UPLOAD_FOLDER" 2> /dev/null)" ]; then
  log_msg "Folder '$UPLOAD_FOLDER' contains files. Adding them to upload list..."

  for file in "$UPLOAD_FOLDER"/*; do
    if [[ $(basename "$file") == *.tar ]]; then
      files_to_upload+=("$file")
    fi
  done

  log_msg "Found ${#files_to_upload[@]} files in upload/ folder - added to upload list."
else
  log_msg "Folder '$UPLOAD_FOLDER' is empty. Loading new snapshots..."
fi

# ==========================================
# PART 1: ANALYSIS AND TRANSFER OF OLD FILES (NEW ONLY)
# ==========================================
declare -A best_files # Keep newest snapshots per system
# Note: We grab files only from the current directory, not upload/
all_new=(*.tar)
shopt -s nullglob

for file in "${all_new[@]}"; do
  system_name="${file%%_*}"
  rest="${file#*_}"
  timestamp="${rest%.tar}"

  if [ -z "${best_files[$system_name]+x}" ]; then
    best_files[$system_name]="$file"
  else
    if [[ "$timestamp" > "${best_files[$system_name]}" ]]; then
      log_msg "Update for $system_name: ${best_files[$system_name]} -> $file"
      best_files[$system_name]="$file"
    fi
  fi
done

# ==========================================
# PART 2: TRANSFERRING OLD FILES TO UPLOAD
# ==========================================
log_msg "Moving older files to catalog '$UPLOAD_FOLDER'..."

for file in "${all_new[@]}"; do
  system_name="${file%%_*}"

  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      log_msg "Moving old file: $file -> ./upload/"
      mv "$file" "$UPLOAD_FOLDER/" || {
        log_msg "Error moving file: $file"
        exit 1
      }
    fi
  else
    log_msg "Warning: System $system_name does not have a saved 'best' file"
  fi
done

# ==========================================
# PART 3: UPLOAD AND DELETION (USING FILES_TO_UPLOAD LIST)
# ==========================================

if [ ${#files_to_upload[@]} -eq 0 ]; then
  log_msg "No files to upload to SSH server."
else
  log_msg "Starting upload of ${#files_to_upload[@]} files to server: $SSH_HOST"

  # Loop through each item in the files_to_upload array
  for local_file in "${files_to_upload[@]}"; do
    remote_name=$(basename "$local_file")

    log_msg "Uploading: $remote_name to $SSH_HOST${REMOTE_DIR}"

    # 1. Sending file via SCP (SRC -> DST)
    if ! scp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "$local_file" \
      "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/${remote_name}" 2>&1 | tee -a "$LOG_FILE"; then
      log_msg "ERROR: Failed to upload file $remote_name!"
      exit 1
    fi

    # 2. Verify existence of file on server (SFTP LS)
    log_msg "Checking if file exists on server..."

    if ! sftp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "${SSH_USER}@${SSH_HOST}" <<< "ls ${REMOTE_DIR}/${remote_name}" 2> /dev/null; then
      log_msg "ERROR: File $remote_name not found on server (sftp ls didn't find file)."
      exit 1
    fi

    # 3. Verification via test -f in SSH
    if ! sftp -i "$SSH_KEY" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=60 \
      "${SSH_USER}@${SSH_HOST}" <<< "test -f ${REMOTE_DIR}/${remote_name} && echo YES || echo NO" 2> /dev/null | grep -q YES; then
      log_msg "ERROR: Verification via test -f did not confirm file $remote_name!"
      exit 1
    fi

    # ==========================================
    # PART 4: REMOVAL OF FILE FROM UPLOAD FOLDER
    # ==========================================

    log_msg "File $remote_name uploaded and verified on server."
    log_msg "Removing file from local folder '$UPLOAD_FOLDER'..."

    if rm "$local_file"; then
      log_msg "File $remote_name removed from upload/ catalog"
    else
      log_msg "ERROR: Failed to remove file $remote_name from upload/ catalog"
    fi
  done

  log_msg "Upload, verification and cleanup operation completed successfully."

fi

log_msg "Cleanup and transfer operation completed."
