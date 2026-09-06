#!/bin/bash

# Ensure zenity is installed (Arch Linux / pacman)
if ! command -v zenity &> /dev/null; then
    echo "Zenity is not installed. Installing..."
    sudo pacman -S --needed --noconfirm zenity
fi

# Open a GUI file selection dialog
FILE_PART=$(zenity --file-selection --title="Select any part of the split backup file (e.g., .aa)")

# Exit if the user cancelled
if [ -z "$FILE_PART" ]; then
    echo "No file selected."
    exit 1
fi

# Strip the trailing extension (e.g., .aa) to get the common base path
BASE_PATH="${FILE_PART%.*}"

# Concatenate all matching parts and extract
cat "${BASE_PATH}".* | sudo tar -xzvf - -C /timeshift/snapshots/
