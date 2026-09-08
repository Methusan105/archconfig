#!/bin/bash

# List required packages (package names match command names on Arch Linux)
REQUIRED_PKGS=(zenity curl tar sudo)
MISSING_PKGS=()

# Check for missing commands
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! command -v "$pkg" &> /dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

# Auto-install any missing tools
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "Missing required package(s): ${MISSING_PKGS[*]}"
    echo "Installing missing dependencies..."
    sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}"
fi

# Ask user for the first URL via GUI
FIRST_URL=$(zenity --entry \
    --title="Timeshift Restore" \
    --text="Enter the URL of the FIRST split part (ending in .001 or .aa):" \
    --entry-text="https://github.com/Methusan105/Personal/releases/download/ALB/timeshift-backup.tar.gz.001")

if [ -z "$FIRST_URL" ]; then
    echo "No URL provided. Exiting."
    exit 0
fi

# Detect numeric extension pattern (.001)
if [[ "$FIRST_URL" =~ \.001$ ]]; then
    prefix="${FIRST_URL%.001}"
    URL_LIST=()
    i=1

    # Auto-detect all sequential parts (.001, .002, ...) via HTTP HEAD checks
    echo "Checking for split archive parts on server..."
    while true; do
        part_url=$(printf "%s.%03d" "$prefix" "$i")
        if curl --output /dev/null --silent --head --fail "$part_url"; then
            URL_LIST+=("$part_url")
            ((i++))
        else
            break
        fi
    done
else
    # Fallback to single URL if not ending in .001
    URL_LIST=("$FIRST_URL")
fi

echo "Found ${#URL_LIST[@]} archive part(s) to stream:"
printf " - %s\n" "${URL_LIST[@]}"

# Stream all sequential parts directly into tar without storing files locally
curl -sL "${URL_LIST[@]}" | sudo tar -xzvf - -C /timeshift/snapshots/

if [ ${PIPESTATUS[0]} -eq 0 ] && [ ${PIPESTATUS[1]} -eq 0 ]; then
    echo "Extraction completed successfully."
else
    echo "An error occurred during extraction." >&2
    exit 1
fi
