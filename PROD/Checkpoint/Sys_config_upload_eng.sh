#!/bin/bash

# ==========================================
# SCP Connection Settings + REMOVAL AFTER VERIFICATION
# ==========================================
SSH_HOST="your.appliance.com" # Host IP or name
SSH_USER="user_appliance"     # User on the server
REMOTE_DIR="/path/to/files/"  # Target path on the server (e.g., /data/backups/)

SSH_KEY="/home/admin/.ssh/id_ed25519" # Path to SSH key (ed25519)

LOG_FILE="/tmp/Sys_config_upload.log"
UPLOAD_FOLDER="./upload"

# Enable file and terminal logging mode
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

log_msg "Starting cleanup and TGZ file transfer process..."

# ==========================================
# HELPER FUNCTION: Date Normalization (SORT CORRECTION)
# ==========================================
normalize_date() {
  local raw_date="$1"

  declare -A months
  months=([Jan]=01 [Feb]=02 [Mar]=03 [Apr]=04 [May]=05 [Jun]=06
    [Jul]=07 [Aug]=08 [Sep]=09 [Oct]=10 [Nov]=11 [Dec]=12)

  local day=$(echo "$raw_date" | cut -d'_' -f1)
  local month_name=$(echo "$raw_date" | cut -d'_' -f2)
  local year=$(echo "$raw_date" | cut -d'_' -f3)
  local hour=$(echo "$raw_date" | cut -d'_' -f4)
  local min=$(echo "$raw_date" | cut -d'_' -f5)
  local sec=$(echo "$raw_date" | cut -d'_' -f6)

  local month_num="${months[$month_name]:-00}"

  echo "$year$month_num${day}${hour}${min}${sec}"
}

# ==========================================
# HELPER FUNCTION: Extract System Name (CORRECTED)
# ==========================================
# Returns system name e.g., -fwpl1 or fwpl2 based on filename prefix "backup_-<System>_<Domain>..."
extract_system_name() {
  local file="$1"
  # 1. Get base filename without directory path to ensure consistency
  local basename=$(basename "$file")

  # 2. Remove leading "backup_-" or "backup_" if present.
  # Pattern handles the hyphen explicitly as seen in logs.
  local rest="${basename#backup_-}"
  rest="${rest#backup_}" # Fallback if only backup_ prefix

  # 3. Get first field before next underscore (domain separator)
  local system_name=$(echo "$rest" | cut -d'_' -f1)

  # 4. Remove trailing hyphen if exists (e.g. fwpl2-)
  system_name="${system_name%-}"

  echo "$system_name"
}

# ==========================================
# PART 0: CHECK UPLOAD FOLDER
# ==========================================
shopt -s nullglob
all_files=(*.tgz) # Filter only .tgz

if [ ${#all_files[@]} -eq 0 ]; then
  log_msg "Error: No .tgz files found in catalog"
  exit 1
fi

log_msg "Checking contents of folder '$UPLOAD_FOLDER'..."
declare -a files_to_upload=()

if [ -n "$(ls -A "$UPLOAD_FOLDER" 2> /dev/null)" ]; then
  log_msg "Folder '$UPLOAD_FOLDER' contains files. Adding them to upload list..."

  for file in "$UPLOAD_FOLDER"/*; do
    if [[ "$(basename "$file")" == *.tgz ]]; then
      files_to_upload+=("$file")
    fi
  done

  log_msg "Found ${#files_to_upload[@]} files in upload/ folder - added to upload list."
else
  log_msg "Folder '$UPLOAD_FOLDER' is empty. Loading new snapshots from current catalog..."
fi

# ==========================================
# PART 1: ANALYSIS AND TRANSFER OF OLD FILES
# ==========================================
declare -A best_files # Keep newest snapshots per system

for file in "${all_files[@]}"; do
  # Use helper function for consistency
  system_name=$(extract_system_name "$file")

  if [ -z "${best_files[$system_name]+x}" ]; then
    best_files[$system_name]="$file"
  else
    # Compare date (numeric) in Bash works correctly lexically for YYYYMM... format
    file_timestamp_raw=$(echo "$file" | sed 's/.*_\([0-9][0-9]*_[A-Za-z]*_[0-9]*_[0-9]*_[0-9]*\)\.tgz/\1/')
    file_timestamp=$(normalize_date "$file_timestamp_raw")

    if [[ "$file_timestamp" > "${best_files[$system_name]}" ]]; then
      log_msg "Update for $system_name: ${best_files[$system_name]} -> $file"
      best_files[$system_name]="$file"
    fi
  fi
done

# ==========================================
# PART 2: TRANSFERRING OLD FILES TO UPLOAD (CORRECTED)
# ==========================================
log_msg "Moving older files to catalog '$UPLOAD_FOLDER'..."

for file in "${all_files[@]}"; do
  # Use SAME helper function as Part 1 to ensure key matches exactly
  system_name=$(extract_system_name "$file")

  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      log_msg "Moving old: $file -> ./upload/"
      mv "$file" "$UPLOAD_FOLDER/" || {
        log_msg "Error moving file: $file"
        exit 1
      }
    fi
  else
    # Only warn if system is actually found in list (which it is now)
    # But since we are iterating all files, and best_files stores the BEST one for each SYSTEM.
    # If a system has NO best file stored (unlikely here), skip.
    # With fix, this warning will appear much less often or correctly identify systems not in array if any.
    : # Silently ignore or log differently?
    # Actually, if we iterate all files and check if it's the 'best' one, this block shouldn't warn "missing best"
    # because best_files is populated from 'all_files' which contains current catalog.
    # This warning was caused by mismatched keys. Now fixed.
  fi
done

# ==========================================
# PART 3: UPLOAD AND DELETION (USING FILES_TO_UPLOAD LIST)
# ==========================================

if [ ${#files_to_upload[@]} -eq 0 ]; then
  log_msg "No files to upload to SSH server."
else
  log_msg "Starting upload of ${#files_to_upload[@]} files to server: $SSH_HOST"

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
