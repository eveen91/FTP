#!/bin/bash
#===============================================================================
# Script: Upload Checkpoint Firewall Snapshots to FTP Server
# Description: Moves latest checkpoint firewall snapshot files to FTP server
#              based on gateway names (e.g., fwpl1, rztdsfwg1)
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipeline failures

# CONFIGURATION SECTION - Modify these paths and settings
SOURCE_DIR="/var/log/CPsnapshot"        # Source directory with .tar files
FTP_SERVER="your.ftp.server.com"         # FTP server hostname/IP
FTP_USER="your_username"                 # FTP username
FTP_PASS="your_password"                 # FTP password (or use -np for no-password)
FTP_REMOTE_DIR="/snapshots"              # Remote directory on FTP server

# OPTIONS
DELETE_AFTER_UPLOAD=true                 # Delete old files after successful upload?
LOG_FILE="/tmp/snapshot_upload.log"      # Log file for tracking progress
DRY_RUN=false                            # Set to true to test without uploading (default: false)
#------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" | tee -a "$LOG_FILE" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

cleanup() {
    error "$0: Script failed! Cleaning up..."
    
    # Clean up any partial uploads on remote server
    sshpass -p "$FTP_PASS" \
        sftp -r "$FTP_USER@${FTP_SERVER}:${FTP_REMOTE_DIR}" <<'EOF_SSH'
cd /
rm -f *.tar
EOF_SSH
    
    error "Cleaned up failed upload on FTP server."
}

trap cleanup EXIT

log "Starting checkpoint snapshot upload process..."
log "Source: $SOURCE_DIR"
log "FTP Server: ${FTP_SERVER}"
log "Remote Path: ${FTP_REMOTE_DIR}"
log "Dry Run Mode: $DRY_RUN"
log "Delete After Upload: $DELETE_AFTER_UPLOAD"

# Ensure source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    error "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Collect all .tar files
mapfile -t tar_files < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.tar" -type f | sort)

if [[ ${#tar_files[@]} -eq 0 ]]; then
    log "No snapshot files found in $SOURCE_DIR"
    exit 0
fi

log "Found ${#tar_files[@]} snapshot files to process."

# Array to store latest file for each gateway
declare -A gateway_latest_files

# Function to extract gateway name from filename
extract_gateway() {
    local filename="$1"
    echo "${filename%_*}"  # Removes everything after the first underscore
}

# Function to parse date/time from filename (YYYY_MM_DD__HH_MM)
parse_timestamp() {
    local filename="$1"
    local base="${filename%.*}"          # Remove .tar extension
    local parts=(${base//\__/ /})        # Split by __ and convert __ to space
    
    if [[ ${#parts[@]} -ge 3 ]]; then
        echo "${parts[0]}-${parts[1]}-${parts[2]}T${parts[3]:0:2}:${parts[4]:0:2}"
    else
        echo ""
    fi
}

# Function to compare two timestamps (returns true if first is newer)
timestamp_is_newer() {
    local ts1="$1"
    local ts2="$2"
    
    [[ -n "$ts1" && -n "$ts2" ]] && [[ "$ts1" > "$ts2" ]]
}

# Process files by gateway, keeping only latest per gateway
log "Processing snapshot files..."

for file in "${tar_files[@]}"; do
    filename=$(basename "$file")
    
    # Extract gateway name (first part before underscore)
    gateway=$(extract_gateway "$filename")
    
    timestamp=$(parse_timestamp "$filename")
    
    log "  Processing: $gateway -> $filename (${timestamp:-no-timestamp})"
    
    # Initialize gateway latest files array if not exists
    if [[ -z "${gateway_latest_files[$gateway]:-}" ]]; then
        gateway_latest_files["$gateway"]="$file"
        log "    Gateway '$gateway' added to tracking (latest: $filename)"
    else
        current_latest="${gateway_latest_files[$gateway]}"
        
        # Compare timestamps or use file size if timestamps not available
        newer=false
        
        if [[ -n "$timestamp" && -n "$(parse_timestamp "$current_latest")" ]]; then
            if timestamp_is_newer "$timestamp" "$(parse_timestamp "$current_latest")"; then
                newer=true
            fi
            
            # Handle same-timestamp scenario (prefer higher file size or alphabetically)
            if [[ "$newer" == false && -n "${timestamp:-}" && -n "$(parse_timestamp "$current_latest")" ]]; then
                current_size=$(stat -c%s "$current_latest" 2>/dev/null || echo "0")
                new_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                
                if [[ $new_size -gt $current_size ]]; then
                    newer=true
                fi
            fi
        fi
        
        if [[ "$newer" == true ]]; then
            log "    Replaced old version with: $filename"
            gateway_latest_files["$gateway"]="$file"
        else
            log "    Keeping existing latest: $(basename "${gateway_latest_files[$gateway]}")"
        fi
    fi
done

log "Snapshot files grouped by gateway. Keeping latest versions:"
for gateway in "${!gateway_latest_files[@]}"; do
    log "  ${gateway}: $(basename "${gateway_latest_files[$gateway]}")"
done

# Upload to FTP server
if [[ "$DRY_RUN" != true ]]; then
    log "\n--- Starting FTP upload ---"
    
    # Remove existing files on remote server if needed (optional)
    if [[ "$DELETE_AFTER_UPLOAD" == true && -d "$FTP_REMOTE_DIR" ]]; then
        log "Cleaning existing files on remote server..."
        sshpass -p "$FTP_PASS" \
            sftp -r "$FTP_USER@${FTP_SERVER}:${FTP_REMOTE_DIR}" <<'EOF_SSH'
rm -f *.tar
EOF_SSH
        
        log "Remote directory cleaned successfully."
    fi
    
    # Create remote directory if it doesn't exist
    sshpass -p "$FTP_PASS" \
        sftp -r "${FTP_USER}@${FTP_SERVER}:${FTP_REMOTE_DIR}" <<'EOF_SSH'
mkdir -p $(dirname ${^2})
EOF_SSH
    
    # Upload all selected latest files
    for file in "${gateway_latest_files[@]}"; do
        if [[ "$DELETE_AFTER_UPLOAD" == true ]]; then
            log "Uploading: $file (will delete old after)"
        else
            log "Uploading: $file"
        fi
        
        sshpass -p "$FTP_PASS" \
            sftp -b -r "$FTP_USER@${FTP_SERVER}:${FTP_REMOTE_DIR}" <<EOF_SSH
put "$file" "${^2}"
EOF_SSH
        
        if [[ $? -eq 0 ]]; then
            log "  Upload successful: $file"
            
            # Delete local file after upload if configured
            if [[ "$DELETE_AFTER_UPLOAD" == true && -f "$file" ]]; then
                log "  Deleting local copy: $file"
                rm -f "$file"
            fi
        else
            error "Upload failed for: $file"
        fi
    done
    
    log "\n--- FTP upload completed ---"
else
    log "\n=== DRY RUN MODE - No files will be uploaded ==="
fi

log "\nUpload process completed."
log "Log file: $LOG_FILE"
