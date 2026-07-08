#!/bin/bash

# Script to group files by month from year-month-day_timestamp.extension format
# Handles symbolic links - moves original files and updates symlinks
# Usage: ./organize_by_month.sh [source_directory] [target_base_directory]

# Set defaults if not provided
SOURCE_DIR="${1:-.}"
TARGET_BASE="${2:-.}"

echo "=== File Organizer by Month ==="
echo "Source directory: $SOURCE_DIR"
echo "Base target directory: $TARGET_BASE"
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
        
        # Construct the month folder name (YYYY-MM)
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
            else
                echo "  -> WARNING: Original file not found at: $original_path. Removing symlink."
                rm "$item"
            fi
        else
            # Regular file - just move it
            mv "$item" "$month_folder/"
            echo "  -> Moved to: $month_folder"
        fi
    else
        echo "  -> WARNING: Could not parse date from filename. Keeping in place."
    fi
done

echo ""
echo "=== Organization Complete ==="
echo ""
echo "Created month folders:"
find "$TARGET_BASE" -type d -name "*-*" | sort
