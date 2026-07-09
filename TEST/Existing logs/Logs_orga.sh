#!/bin/bash

# Get current date as YYYY-MM-DD format
current_date=$(date +%Y-%m-%d)

# Define a function to extract year and month from filename
extract_year_month() {
  local file=$1
  echo ${file:0:7} # Extract YYYY-MM
}

# Loop over all adtlog* files
for file in *.adtlog*; do
  # Resolve symlink if it is a symlink
  if [ -L "$file" ]; then
    file=$(readlink -f "$file")
  fi

  # Skip if the file doesn't match the expected pattern
  if ! [[ $file =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_.* ]]; then
    echo "Skipping invalid filename: $file"
    continue
  fi

  # Extract year and month from filename
  file_year_month=$(extract_year_month "$file")

  # Compare dates
  if [[ $(date -d "$current_date" +%s) -gt $(date -d "+3 months" +%s) ]]; then
    echo "File $file is older than 3 months."

    # Check if the YEAR directory already exists, if not create it
    YEAR=${file_year_month:0:4}
    if [ ! -d "$YEAR" ]; then
      mkdir "$YEAR"
    fi

    # Extract month from filename (characters 5-6)
    MONTH=${file_year_month:5:2}

    # Check if the MONTH directory already exists within the YEAR directory, if not create it
    if [ ! -d "$YEAR/$MONTH" ]; then
      mkdir "$YEAR/$MONTH"
    fi

    # Move the file into the correct folder
    mv "$file" "$YEAR/$MONTH/"
  else
    echo "File $file is newer than 3 months."
  fi
done

# Function to archive a directory into a .tar.gz file
archive_month() {
  local year=$1
  local month=$2
  local dir="$year/$month"

  if [ -d "$dir" ]; then
    tar -czf "${dir}.tar.gz" -C "$year" "$month"
    rm -r "$dir"
    echo "Archived $dir to ${dir}.tar.gz and removed the directory."
  else
    echo "Directory $dir does not exist."
  fi
}

# Loop over all YEAR directories
for year in [0-9][0-9][0-9][0-9]; do
  if [ -d "$year" ]; then
    # Loop over all MONTH directories within the YEAR directory
    for month in [0-1][0-9]; do
      archive_month "$year" "$month"
    done
  fi
done
