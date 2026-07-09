#!/bin/bash

# Loop over all adtlog* files
for file in *.adtlog*; do
  # Resolve symlink if it is a symlink
  if [ -L "$file" ]; then
    file=$(readlink -f "$file")
  fi

  # Extract year from filename (characters 1-4)
  YEAR=${file:0:4}

  # Check if the YEAR directory already exists, if not create it
  if [ ! -d "$YEAR" ]; then
    mkdir "$YEAR"
  fi

  # Extract month from filename (characters 5-6)
  MONTH=${file:5:2}

  # Check if the MONTH directory already exists within the YEAR directory, if not create it
  if [ ! -d "$YEAR/$MONTH" ]; then
    mkdir "$YEAR/$MONTH"
  fi

  # Move the file into the correct folder
  mv "$file" "$YEAR/$MONTH/"
done
