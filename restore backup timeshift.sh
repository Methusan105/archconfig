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

# Ask user for GitHub Personal Access Token (PAT)
GITHUB_TOKEN=$(zenity --password \
    --title="GitHub Authentication" \
    --text="Enter your GitHub Personal Access Token (leave blank for public repos):")

# Prepare curl authorization header argument if token is provided
AUTH_HEADER=()
if [ -n "$GITHUB_TOKEN" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")
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
        if curl "${AUTH_HEADER[@]}" --output /dev/null --silent --head --fail "$part_url"; then
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

if [ ${#URL_LIST[@]} -eq 0 ]; then
    echo "No accessible files found at the specified URL." >&2
    exit 1
fi

echo "Found ${#URL_LIST[@]} archive part(s) to stream:"
printf " - %s\n" "${URL_LIST[@]}"

# Ensure destination directory exists before extracting
sudo mkdir -p /timeshift/snapshots/

# Stream all sequential parts directly into tar without storing files locally
curl "${AUTH_HEADER[@]}" -sL "${URL_LIST[@]}" | sudo tar -xzvf - -C /timeshift/snapshots/

# Capture pipeline status safely
pipe_status=("${PIPESTATUS[@]}")

# Safely check execution status using double brackets [[ ]]
if [[ "${pipe_status[0]:-1}" -eq 0 && "${pipe_status[1]:-1}" -eq 0 ]]; then
    echo "Extraction completed successfully."
else
    echo "An error occurred during extraction." >&2
    exit 1
fi
