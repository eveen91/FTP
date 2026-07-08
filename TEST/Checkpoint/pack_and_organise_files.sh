#!/bin/bash

# Combined Script: Organize files by month and pack into tar.gz archives
# Usage: ./combine_scripts.sh [source_directory] [target_base_directory]
# If no arguments provided, defaults to current directory

set -e

# Set defaults if not provided
SOURCE_DIR="${1:-.}"
TARGET_BASE="${2:-.}"

# ==========================================
# SFTP upload configuration
# ==========================================
# Fill these in (or export them as environment variables before running the script).
SFTP_HOST="${SFTP_HOST:-}" # e.g. "ftp.example.com"
SFTP_PORT="${SFTP_PORT:-22}"
SFTP_USER="${SFTP_USER:-}"                     # e.g. "myuser"
SFTP_REMOTE_DIR="${SFTP_REMOTE_DIR:-/uploads}" # remote directory to upload into
SFTP_KEY="${SFTP_KEY:-}"                       # path to private key, e.g. "$HOME/.ssh/id_rsa" (leave empty to use ssh-agent/default key)
UPLOAD_TO_SFTP="${UPLOAD_TO_SFTP:-false}"      # set to "true" to enable Phase 3 upload

# ==========================================
# Logging configuration
# ==========================================
LOG_DIR="/home/fwbackup"
mkdir -p "$LOG_DIR"
RUN_TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
LOG_FILE="$LOG_DIR/backup_log_${RUN_TIMESTAMP}.log"

# Logs a message to both the console and the log file, with a timestamp in the file.
log() {
  local msg="$1"
  echo "$msg"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
}

log "=========================================="
log "  Run started: $RUN_TIMESTAMP"
log "  Log file: $LOG_FILE"
log "=========================================="

echo "=========================================="
echo "  File Organizer & Archive Creator"
echo "=========================================="
echo ""
echo "Source directory: $SOURCE_DIR"
echo "Target base directory: $TARGET_BASE"
echo ""

# Check if source directory exists and is a directory
if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: Source directory '$SOURCE_DIR' does not exist or is not a directory."
  exit 1
fi

# Create target base directory if it doesn't exist
mkdir -p "$TARGET_BASE"
echo "Created/verified target base directory: $TARGET_BASE"

# Navigate to source directory
cd "$SOURCE_DIR" || exit 1

# ==========================================
# PHASE 1: Organize files by month
# ==========================================
echo ""
echo "=========================================="
echo "PHASE 1: Organizing files into month folders"
echo "=========================================="

# Process each file with year-month-date in name
for item in *; do
  # Skip if not a regular file OR symbolic link
  if [ ! -L "$item" ] && [ ! -f "$item" ]; then
    continue
  fi

  echo "Processing: $item"

  # Extract the date portion from filename using regex pattern
  # Pattern: YYYY-MM-DD_timestamp.extension or YYYY-MM-DD_HHMMSS_extension
  if [[ $item =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_[^\.]+\.([^.]+)$ ]]; then
    year="${BASH_REMATCH[1]}"
    month="${BASH_REMATCH[2]}"

    # Create folder name as just MM (e.g., "03/" instead of "2024-03/")
    # Archive will still be named YYYY-MM.tar.gz (e.g., "2024-03.tar.gz")
    month_folder="$TARGET_BASE/$month"

    # Create the month directory if it doesn't exist
    mkdir -p "$month_folder"

    # Determine if this is a symbolic link or regular file
    if [ -L "$item" ]; then
      original_path=$(readlink -f "$item")

      if [ -f "$original_path" ]; then
        echo "  -> Symbolic link detected. Moving original file: $(basename "$original_path")"
        mv "$original_path" "$month_folder/"
        # Remove the symlink after moving original file
        rm "$item"
        echo "  -> Removed symlink"
        log "MOVED (symlink target): $(basename "$original_path") -> $month_folder/"
      else
        echo "  -> WARNING: Original file not found at: $original_path. Removing symlink."
        rm "$item"
        log "WARNING: symlink '$item' target '$original_path' not found; symlink removed, nothing moved."
      fi
    else
      # Regular file - just move it
      mv "$item" "$month_folder/"
      echo "  -> Moved to: $month_folder"
      log "MOVED: $item -> $month_folder/"
    fi
  else
    echo "  -> WARNING: Could not parse date from filename. Keeping in place."
    log "SKIPPED (no date match): $item kept in place."
  fi
done

# ==========================================
# PHASE 2: Pack month folders into tar.gz with yyyy-mm archive naming
# ==========================================
echo ""
echo "=========================================="
echo "PHASE 2: Packing month folders into tar.gz archives"
echo "(Folder: MM/, Archive: YYYY-MM.tar.gz)"
echo "=========================================="

month_count=0

for month_folder in "$TARGET_BASE"/*/; do
  if [ -d "$month_folder" ]; then
    folder_name=$(basename "$month_folder")

    # Parse year-month from folder name (YYYY-MM.tar.gz format)
    archive_name="${folder_name}.tar.gz"
    full_archive_path="${TARGET_BASE}/${archive_name}"

    # Remove any existing file at this path first
    rm -f "$full_archive_path"

    # Create tar.gz archive using the MM folder name but YYYY-MM in archive filename
    echo "  Packing contents of $folder_name (MM format) into $archive_name (YYYY-MM format)"
    tar -czf "$full_archive_path" \
      -C "$TARGET_BASE" \
      "$folder_name"

    archive_size=$(du -h "$full_archive_path" | cut -f1)
    echo "  ✓ Created: $archive_name ($archive_size)"
    log "ARCHIVED: folder '$folder_name/' -> $full_archive_path ($archive_size)"
    month_count=$((month_count + 1))
  fi
done

echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo ""
echo "Created month archives:"
for archive in $(ls -1 "$TARGET_BASE"/*.tar.gz 2> /dev/null | sort); do
  size=$(du -h "$archive" | cut -f1)
  name=$(basename "$archive")
  echo "  - $name ($size)"
done

# ==========================================
# PHASE 3: Upload archives to SFTP server
# ==========================================
upload_to_sftp() {
  local host="$1"
  local port="$2"
  local user="$3"
  local remote_dir="$4"
  local key="$5"
  shift 5
  local files=("$@")

  if [ -z "$host" ] || [ -z "$user" ]; then
    echo "Error: SFTP_HOST and SFTP_USER must be set to upload files." >&2
    log "ERROR: upload skipped, SFTP_HOST and/or SFTP_USER not configured."
    return 1
  fi

  if [ ${#files[@]} -eq 0 ]; then
    echo "No archives found to upload."
    log "No archives found to upload."
    return 0
  fi

  # Build the sftp command, optionally adding an identity file
  local sftp_cmd=(sftp -P "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  if [ -n "$key" ]; then
    sftp_cmd+=(-i "$key")
  fi
  sftp_cmd+=("${user}@${host}")

  echo "Connecting to ${user}@${host}:${port} ..."

  # Make sure the remote directory exists (ignore failure if it already does)
  local mkdir_batch
  mkdir_batch="$(mktemp)"
  printf '%s\n' "-mkdir $remote_dir" "bye" > "$mkdir_batch"
  "${sftp_cmd[@]}" -b "$mkdir_batch" > /dev/null 2>&1 || true
  rm -f "$mkdir_batch"

  # Upload each file individually so success/failure can be logged per file
  local overall_status=0
  local f name batch_file
  for f in "${files[@]}"; do
    name="$(basename "$f")"
    batch_file="$(mktemp)"
    printf '%s\n' "put \"$f\" \"$remote_dir/\"" "bye" > "$batch_file"

    if "${sftp_cmd[@]}" -b "$batch_file" > /dev/null 2>&1; then
      echo "  ✓ Uploaded: $name -> ${host}:${remote_dir}/"
      log "UPLOADED (SFTP): $name -> ${user}@${host}:${remote_dir}/"
    else
      echo "  ✗ Failed to upload: $name" >&2
      log "ERROR: failed to upload $name to ${user}@${host}:${remote_dir}/"
      overall_status=1
    fi
    rm -f "$batch_file"
  done

  return $overall_status
}

if [ "$UPLOAD_TO_SFTP" = "true" ]; then
  echo ""
  echo "=========================================="
  echo "PHASE 3: Uploading archives via SFTP"
  echo "=========================================="

  mapfile -t archives_to_upload < <(ls -1 "$TARGET_BASE"/*.tar.gz 2> /dev/null | sort)

  upload_to_sftp "$SFTP_HOST" "$SFTP_PORT" "$SFTP_USER" "$SFTP_REMOTE_DIR" "$SFTP_KEY" "${archives_to_upload[@]}"
else
  echo ""
  echo "(SFTP upload skipped. Set UPLOAD_TO_SFTP=true and configure SFTP_HOST/SFTP_USER to enable it.)"
  log "SFTP upload skipped (UPLOAD_TO_SFTP is not 'true')."
fi

log "=========================================="
log "  Run finished: $(date '+%Y-%m-%d_%H%M%S')"
log "=========================================="
