#!/bin/bash

# CONFIGURATION
SOURCE_DIR="."          # Where your backup files are currently located
ARCHIVE_DIR="./archive" # Directory to move old backups to (acts as 'upload' folder)

# Check if source directory is not empty of .tgz files
if [[ -z "$(ls -A $SOURCE_DIR 2> /dev/null)" ]]; then
  echo "Source directory appears to be empty."
  exit 1
fi

# Create archive directory if it doesn't exist
mkdir -p "$ARCHIVE_DIR"

echo "Starting backup cleanup..."
echo "Keeping: Newest .tgz per firewall ID"
echo "Moving: Older backups to $ARCHIVE_DIR"

declare -A keep_files   # Associative array to store the newest file path for each ID
declare -A latest_times # Associative array to store the timestamp of the newest file for each ID

# Loop through all matching files (handling spaces safely)
while IFS= read -r -d '' file; do
  # Extract the Firewall ID from the filename
  # Pattern logic: We look for the segment between 'backup_-' and the next '_'
  # Regex explanation:
  # ^.*\(backup_\)-\K[^_-]+(?=-) is a PCRE regex, but we use simpler sed below.
  # This sed command extracts the first part of the ID pair (e.g., fwpl1)
  id=$(basename "$file" | sed 's/.*\(backup_\)-\([^_-]*\)-.*/\2/')

  # Get file creation/modification time in seconds since epoch
  # Note: On Linux stat -c %Y is standard. On macOS/BSD use stat -f %m
  # Using GNU coreutils logic usually safe for servers, fallback provided below
  if [[ $(uname) == *"Darwin"* ]]; then
    mtime=$(stat -f %m "$file")
  else
    mtime=$(stat -c %Y "$file")
  fi

  # Check if we need to update the 'newest' for this ID
  if [[ ! -v keep_files["$id"] ]]; then
    # First file found with this ID, automatically keep it
    keep_files["$id"]="$file"
    latest_times["$id"]="$mtime"
  else
    existing_file="${keep_files[$id]}"
    existing_time="${latest_times[$id]}"

    if [[ "$mtime" -gt "$existing_time" ]]; then
      # Newer file found, switch to it
      keep_files["$id"]="$file"
      latest_times["$id"]="$mtime"
    fi
  fi
done < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.tgz" -print0)

# Move all files that are NOT in the 'keep' array to the archive directory
echo ""
echo "Moving older backups..."
for file in "${!keep_files[@]}"; do
  # Skip files if they still exist (sanity check)
  [[ -f "$file" ]] || continue

  # Verify it was actually a non-newest file by checking existence logic
  # Wait, the loop above only stored NEWEST. So we need to iterate ALL found files
  # and remove them from the 'keep' set if they are not kept.
done

# Correct logic: Iterate through ALL files again to decide what to move
echo ""
echo "Scanning for files to archive..."
for file in $(find "$SOURCE_DIR" -maxdepth 1 -name "*.tgz"); do
  # Extract ID again
  id=$(basename "$file" | sed 's/.*\(backup_\)-\([^_-]*\)-.*/\2/')

  # Check if this file is currently marked as 'kept'
  if [[ "${keep_files[$id]}" != "$file" ]]; then
    echo "Moving (Old): $file"
    mv "$file" "$ARCHIVE_DIR/"
    # Remove from list logic handled implicitly by not touching 'keep_files'
  else
    echo "Keeping:   $file"
  fi
done

echo ""
echo "Cleanup finished. Check $ARCHIVE_DIR for moved files."
