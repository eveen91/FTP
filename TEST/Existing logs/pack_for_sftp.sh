#!/bin/bash

# Script to pack files into tar.gz archives for SFTP transfer
# Usage: ./pack_for_sftp.sh [source_directory] [target_base_directory] [sftp_host] [sftp_user] [remote_dir]

set -e  # Exit on error

SOURCE_DIR="${1:-.}"
TARGET_BASE="${2:-.}"
SFTP_HOST="${3:-host.example.com}"
SFTP_USER="${4:-username}"
REMOTE_DIR="${5:-/remote/path}"

echo "=== SFTP Archive Packager (tar.gz) ==="
echo "Source directory: $SOURCE_DIR"
echo "Target base: $TARGET_BASE"
echo "SFTP Host: $SFTP_HOST"
echo "Remote directory: $REMOTE_DIR"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Check for SFTP utilities
if ! command -v sftp &> /dev/null; then
    echo "Error: sftp is not installed. Please install openssh-client."
    echo "On Ubuntu/Debian: sudo apt-get install openssh-client"
    echo "On macOS: brew install openssh"
    exit 1
fi

# Get list of items to archive (directories, excluding files)
echo "=== Scanning for archives to create ==="
FILE_LIST=()

for item in "$TARGET_BASE"/*; do
    if [ -d "$item" ]; then
        # Only include month folders (MM format)
        if [[ $item =~ ^"$TARGET_BASE"/[0-9][0-9]$ ]]; then
            FILE_LIST+=("$item")
            echo "Found: $(basename "$item")"
        fi
    fi
done

echo ""
if [ ${#FILE_LIST[@]} -eq 0 ]; then
    echo "No month folders found. Exiting."
    exit 0
fi

# Create tar.gz archives for each folder
for source_folder in "${FILE_LIST[@]}"; do
    relative_path=${source_folder#$TARGET_BASE/}
    dest_folder="$relative_path"
    
    echo "Processing: $dest_folder"
    
    # Remove trailing slash from path if exists
    archive_path=$(basename "$source_folder")
    archive_file="${archive_path}.tar.gz"
    
    # Create the archive in place
    echo "  Creating archive: ${archive_path}/$(basename "${source_folder}"*)/.tar.gz"
    cd "$TARGET_BASE"
    tar -czf "${relative_path}/.tar.gz" "${relative_path}/*" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  -> Archive created successfully: ${archive_path}.tar.gz"
        echo ""
        ls -lh "${TARGET_BASE}/${archive_path}"/*.tar.gz
    else
        echo "  -> Error creating archive. Continuing..."
    fi
done

echo ""
echo "=== Archives Created ==="
echo ""
echo "Review the created archives before uploading to SFTP."
echo ""
echo "To upload all archives, you can run:"
echo "  sftp ${SFTP_USER}@${SFTP_HOST}"
echo "  cd ${REMOTE_DIR}"
echo "  put ${TARGET_BASE}/*.tar.gz"
#!/bin/bash

# Script to pack files into archives and prepare for SFTP transfer
# Usage: ./pack_for_sftp.sh [source_directory] [target_base_directory] [sftp_host]

set -e  # Exit on error

SOURCE_DIR="${1:-.}"
TARGET_BASE="${2:-.}"
SFTP_HOST="${3:-host.example.com}"
SFTP_USER="${4:-username}"
REMOTE_DIR="${5:-/remote/path}"
ARCHIVE_FORMAT="${6:-tar}"  # Options: tar, gzip, tgz, zip

echo "=== SFTP Archive Packager ==="
echo "Source directory: $SOURCE_DIR"
echo "Target base: $TARGET_BASE"
echo "SFTP Host: $SFTP_HOST"
echo "Remote directory: $REMOTE_DIR"
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Determine archive command based on format
case "$ARCHIVE_FORMAT" in
    tar)
        ARCHIVE_CMD="tar -czf"
        EXT=".tar.gz"
        ;;
    tgz)
        ARCHIVE_CMD="tar -czf"
        EXT=".tar.gz"
        ;;
    zip)
        ARCHIVE_CMD="zip -r"
        EXT=".zip"
        ;;
    *)
        echo "Unknown archive format: $ARCHIVE_FORMAT"
        echo "Available formats: tar, tgz, zip"
        exit 1
        ;;
esac

# Check for SFTP utilities
if ! command -v sftp &> /dev/null; then
    echo "Error: sftp is not installed. Please install openssh-client."
    echo "On Ubuntu/Debian: sudo apt-get install openssh-client"
    echo "On macOS: brew install openssh"
    exit 1
fi

# Get list of files to archive (files or directories)
echo "=== Scanning for archives to create ==="
FILE_LIST=()

for item in "$TARGET_BASE"/*; do
    if [ -f "$item" ]; then
        FILE_LIST+=("$item")
    elif [ -d "$item" ] && [[ $item =~ ^"$TARGET_BASE"/[0-9][0-9]$ ]]; then
        # Month folder (e.g., 10, 09)
        FILE_LIST+=("$item")
    fi
done

echo "Found ${#FILE_LIST[@]} item(s) to archive"
echo ""

if [ ${#FILE_LIST[@]} -eq 0 ]; then
    echo "No items found to archive. Exiting."
    exit 0
fi

# Create archives for each month folder or single file
for source_item in "${FILE_LIST[@]}"; do
    # Determine what kind of item this is
    if [ -f "$source_item" ]; then
        filename=$(basename "$source_item")
        dest_folder=".$filename"  # Archive name will be based on filename
    else
        # Month folder (e.g., /path/to/base/10)
        relative_path=${source_item#$TARGET_BASE/}
        dest_folder="$relative_path"
    fi
    
    echo "Processing: $dest_folder"
    
    # Create archive name
    base_name="${dest_folder%.}"  # Remove trailing slash if any
    archive_file="$base_name$EXT"
    
    # Create the archive
    echo "  Creating archive: $archive_file"
    "$ARCHIVE_CMD" "$archive_file" "${source_item}/*" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  -> Archive created successfully"
    else
        echo "  -> Error creating archive. Continuing..."
        continue
    fi
done

echo ""
echo "=== Archives Created ==="
ls -lh "$TARGET_BASE"/*$EXT 2>/dev/null | awk '{print $9, $5}' || true

echo ""
echo "Note: Review the archives before uploading to SFTP."
echo "You can modify sftp_host, sftp_user, and remote_dir in this script"
echo "as needed for your environment."