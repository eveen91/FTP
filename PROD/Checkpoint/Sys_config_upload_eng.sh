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
# Input format in filename: DD_Mon_YYYY_HH_MM_SS (e.g., 22_May_2026_10_10_04)
# Outputs a comparable format: YYYY_MM_DD_HH_MM_SS
normalize_date() {
  local raw_date="$1"

  # Define months as numbers (US/EN)
  declare -A months
  months=([Jan]=01 [Feb]=02 [Mar]=03 [Apr]=04 [May]=05 [Jun]=06
    [Jul]=07 [Aug]=08 [Sep]=09 [Oct]=10 [Nov]=11 [Dec]=12)

  # Parse: split by underscore
  local day=$(echo "$raw_date" | cut -d'_' -f1)
  local month_name=$(echo "$raw_date" | cut -d'_' -f2)
  local year=$(echo "$raw_date" | cut -d'_' -f3)
  local hour=$(echo "$raw_date" | cut -d'_' -f4)
  local min=$(echo "$raw_date" | cut -d'_' -f5)
  local sec=$(echo "$raw_date" | cut -d'_' -f6)

  # Convert month to number
  local month_num="${months[$month_name]:-00}"

  # Return lexically comparable string (YYYY_MM_DD...)
  echo "$year$month_num${day}${hour}${min}${sec}"
}

# ==========================================
# PART 0: CHECK UPLOAD FOLDER
# ==========================================

shopt -s nullglob
all_files=(*.tgz) # Filter only .tgz (change to *.tar or *.tgz if needed)

if [ ${#all_files[@]} -eq 0 ]; then
  log_msg "Error: No .tgz files found in catalog"
  exit 1
fi

log_msg "Checking contents of folder '$UPLOAD_FOLDER'..."

declare -a files_to_upload=()

# If upload folder is not empty, add existing files to upload list
if [ -n "$(ls -A "$UPLOAD_FOLDER" 2> /dev/null)" ]; then
  log_msg "Folder '$UPLOAD_FOLDER' contains files. Adding them to upload list..."

  for file in "$UPLOAD_FOLDER"/*; do
    # Check extension (set above)
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
declare -A best_files # Keep newest snapshots per system (for files in current catalog)

for file in "${all_files[@]}"; do
  # Extract System Name from new format: backup_-<system>_<domain>.<date>.tgz
  # Remove "backup_" and first part after hyphen before second underscore section (domain)
  # Example: backup_-fwpl2-_... -> system = fwpl2

  local_name="${file#*_}" # Remove first segment name if in loop, but here it's full path
  # Simple logic: remove "backup_" at beginning
  local_rest="${local_name#backup_-}"
  # System is the part before next "_" (before domain) or before date.
  # Format suggests: backup_-SYSTEM-_DOMAIN.DOMAIN.DATE...
  # Split by "_" and take second part? No, better find SYSTEM segment.

  # Safer extraction for this specific format:
  # 1. Remove "backup_-" (if exists) or "backup_"
  rest="${local_name#backup_-}"
  # Rest is e.g.: fwpl2-_fwpl2.erv-global.net_22_May_2026...

  # System found before next underscore "_" that starts domain/date section
  system_name=$(echo "$rest" | cut -d'_' -f1) # First part: fwpl2

  # Remove trailing hyphen if exists (e.g. fwpl2-)
  system_name="${system_name%-}"

  # Get date/time for comparison
  # Format in name: _DD_Mon_YYYY_HH_MM_SS.tgz (part after second underscore before extension)
  file_timestamp_raw=$(echo "$file" | sed 's/.*_\([0-9][0-9]*_[A-Za-z]*_[0-9]*_[0-9]*_[0-9]*\)\.tgz/\1/')

  # Normalize date to number (e.g., 2026_05_22...)
  file_timestamp=$(normalize_date "$file_timestamp_raw")

  if [ -z "${best_files[$system_name]+x}" ]; then
    best_files[$system_name]="$file"
  else
    # Compare date (numeric) in Bash works correctly lexically for YYYYMM... format
    if [[ "$file_timestamp" > "${best_files[$system_name]}" ]]; then
      log_msg "Update for $system_name: ${best_files[$system_name]} -> $file"
      best_files[$system_name]="$file"
    fi
  fi
done

# ==========================================
# PART 2: TRANSFERRING OLD FILES TO UPLOAD
# ==========================================
log_msg "Moving older files to catalog '$UPLOAD_FOLDER'..."

for file in "${all_files[@]}"; do
  system_name=$(echo "$file" | sed 's/.*_-//; s/_/\./1') # Extract system name from new format

  # Since we already read best_files for this system above, check if this file is not the best one
  if [ -n "${best_files[$system_name]+x}" ]; then
    if [[ "$file" != "${best_files[$system_name]}" ]]; then
      log_msg "Moving old: $file -> ./upload/"
      mv "$file" "$UPLOAD_FOLDER/" || {
        log_msg "Error moving file: $file"
        exit 1
      }
    fi
  else
    log_msg "Warning: System $system_name does not have saved 'best' file (not in array)"
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
    # Using SSH key and batch mode
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
