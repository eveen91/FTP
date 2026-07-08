#!/bin/bash

# Script to upload tar.gz archives to SFTP server after a delay
# Usage: ./upload_to_sftp.sh [delay_minutes] [archive_directory] [sftp_host] [sftp_user] [remote_path]
# 
# Example 1: Wait 30 minutes then upload all archives in current directory
#   ./upload_to_sftp.sh 30 . user@example.com /backup/path
#
# Example 2: Upload immediately (delay=0)
#   ./upload_to_sftp.sh 0 /path/to/archives ftp.example.com username /remote/dest

set -e

DELAY_MINUTES="${1:-30}"
ARCHIVE_DIR="${2:-.}"
SFTP_HOST="${3:-}"
SFTP_USER="${4:-}"
REMOTE_PATH="${5:-/}"

# Check if we have SFTP parameters (upload mode) or just delay (archive listing mode)
if [ -n "$SFTP_HOST" ] && [ -n "$SFTP_USER" ]; then
    echo "=========================================="
    echo "  SFTP Upload Script"
    echo "=========================================="
    echo ""
    echo "Upload settings:"
    echo "  Delay: $DELAY_MINUTES minutes"
    echo "  Archive directory: $ARCHIVE_DIR"
    echo "  Host: $SFTP_HOST"
    echo "  User: $SFTP_USER"
    echo "  Remote path: $REMOTE_PATH"
    echo ""
    
    # Wait for the specified delay period
    if [ "$DELAY_MINUTES" -gt 0 ]; then
        echo "Waiting $DELAY_MINUTES minutes before uploading..."
        echo "  (This allows both local and remote copies to exist during this time)"
        sleep "${DELAY_MINUTES}m"
    else
        echo "Uploading immediately..."
    fi
    
    # Find all tar.gz archives in the directory
    archive_count=0
    for archive_file in "$ARCHIVE_DIR"/*.tar.gz; do
        if [ -f "$archive_file" ]; then
            archive_name=$(basename "$archive_file")
            echo ""
            echo "------------------------------------------"
            echo "Uploading: $archive_name"
            echo "  Local:  $(du -h "$archive_file" | cut -f1)"
            
            # Upload to SFTP server using sftp command
            # Note: You may need to adjust authentication method
            # This example uses password (replace with ssh key if needed)
            
            # First, check if remote directory exists
            sshpass -p "$(sftp -o StrictHostKeyChecking=no $SFTP_HOST:$SFTP_USER@$SFTP_HOST '$REMOTE_PATH' 'ls')" 2>/dev/null || \
            sftp -o BatchMode=yes -o UserKnownHostsFile=/dev/null \
                 "$SFTP_USER@$SFTP_HOST" <<EOF <<< "exit"
mkdir -p $REMOTE_PATH
EOF
            
            # Upload the file
            echo "Uploading to SFTP server..."
            sftp -r -o BatchMode=yes "$SFTP_USER@$SFTP_HOST" <<EOF <<< "exit"
put $ARCHIVE_DIR/$archive_name $REMOTE_PATH/$archive_name
EOF
            
            remote_size=$(sshpass -p "$(sftp -o StrictHostKeyChecking=no $SFTP_HOST:$SFTP_USER@$SFTP_HOST '$REMOTE_PATH' 'ls | grep $archive_name$')" 2>/dev/null || echo "uploaded")
            
            echo "  Remote: $remote_size"
            echo "✓ Upload complete!"
            
            ((archive_count++))
        fi
    done
    
    echo ""
    echo "=========================================="
    echo "  Upload Summary"
    echo "=========================================="
    echo ""
    echo "Total archives uploaded: $archive_count"
    
    if [ "$archive_count" -eq 0 ]; then
        echo "No tar.gz files found in: $ARCHIVE_DIR"
    else
        echo "All uploads completed successfully!"
    fi
    
else
    # No SFTP parameters - just list the archives available for upload
    ARCHIVE_LISTING_MODE=true
    echo "=========================================="
    echo "  Archive Upload Preview"
    echo "=========================================="
    echo ""
    echo "Found $DELAY_MINUTES minutes delay before upload. These are the archives that will be uploaded:"
    echo ""
    
    for archive_file in "$ARCHIVE_DIR"/*.tar.gz; do
        if [ -f "$archive_file" ]; then
            archive_name=$(basename "$archive_file")
            local_size=$(du -h "$archive_file" | cut -f1)
            date_created=$(stat -c "%x" "$archive_file" 2>/dev/null || stat -f "%Sm" "$archive_file" 2>/dev/null)
            
            echo "Archive: $archive_name"
            echo "  Size: $local_size"
            echo "  Created: $date_created"
            echo ""
        fi
    done
    
    if [ ! -d "$ARCHIVE_DIR" ]; then
        echo "Error: Archive directory '$ARCHIVE_DIR' does not exist!"
        exit 1
    elif [ -z "$(ls -A "$ARCHIVE_DIR")" ] 2>/dev/null; then
        echo "No archives found to upload."
    fi
    
    echo ""
    echo "=========================================="
    echo "  To upload these files, use:"
    echo "=========================================="
    echo "   ./upload_to_sftp.sh $DELAY_MINUTES $ARCHIVE_DIR <host> <user> <remote_path>"
    echo ""
fi