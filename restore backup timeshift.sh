#!/bin/bash

# List required packages (package names match command names on Arch Linux)
REQUIRED_PKGS=(zenity curl tar sudo jq)
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
    --text="Enter your GitHub Personal Access Token (PAT):")

if [ -z "$GITHUB_TOKEN" ]; then
    echo "A GitHub Token is required to access private repositories. Exiting." >&2
    exit 1
fi

# Ask user for the web URL or first file name
INPUT_URL=$(zenity --entry \
    --title="Timeshift Restore" \
    --text="Enter the Release URL or Asset URL (ending in .001):" \
    --entry-text="https://github.com/Methusan105/Personal/releases/download/ALB/timeshift-backup.tar.gz.001")

if [ -z "$INPUT_URL" ]; then
    echo "No URL provided. Exiting."
    exit 0
fi

# Parse Owner, Repo, and Tag from the standard web URL
# Pattern: https://github.com/OWNER/REPO/releases/download/TAG/FILENAME
if [[ "$INPUT_URL" =~ github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    TAG="${BASH_REMATCH[3]}"
    FIRST_FILE="${BASH_REMATCH[4]}"
else
    echo "Invalid GitHub Release URL format." >&2
    exit 1
fi

echo "Fetching release metadata via GitHub API..."

# Query the GitHub API for the specified release tag
RELEASE_INFO=$(curl -sH "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$OWNER/$REPO/releases/tags/$TAG")

# Check if release was found
if echo "$RELEASE_INFO" | grep -q "Not Found"; then
    echo "Error: Release or repository not found. Verify your PAT permissions and repository name." >&2
    exit 1
fi

# Base filename prefix if numeric .001 pattern
if [[ "$FIRST_FILE" =~ \.001$ ]]; then
    BASE_NAME="${FIRST_FILE%.001}"
    
    # Extract asset API URLs sequentially using jq
    ASSET_URLS=()
    i=1
    while true; do
        target_file=$(printf "%s.%03d" "$BASE_NAME" "$i")
        asset_url=$(echo "$RELEASE_INFO" | jq -r --arg fn "$target_file" '.assets[] | select(.name == $fn) | .url')
        
        if [ -n "$asset_url" ] && [ "$asset_url" != "null" ]; then
            ASSET_URLS+=("$asset_url")
            ((i++))
        else
            break
        fi
    done
else
    # Single file fallback
    asset_url=$(echo "$RELEASE_INFO" | jq -r --arg fn "$FIRST_FILE" '.assets[] | select(.name == $fn) | .url')
    if [ -n "$asset_url" ] && [ "$asset_url" != "null" ]; then
        ASSET_URLS=("$asset_url")
    else
        ASSET_URLS=()
    fi
fi

if [ ${#ASSET_URLS[@]} -eq 0 ]; then
    echo "No matching asset files found in release '$TAG'." >&2
    exit 1
fi

echo "Found ${#ASSET_URLS[@]} archive part(s) to stream."

# Ensure destination directory exists
sudo mkdir -p /timeshift/snapshots/

# Function to stream API assets into standard output
stream_assets() {
    for url in "${ASSET_URLS[@]}"; do
        curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" \
             -H "Accept: application/octet-stream" \
             "$url"
    done
}

# Stream all parts directly into tar
stream_assets | sudo tar -xzvf - -C /timeshift/snapshots/

pipe_status=("${PIPESTATUS[@]}")

if [[ "${pipe_status[0]:-1}" -eq 0 && "${pipe_status[1]:-1}" -eq 0 ]]; then
    echo "Extraction completed successfully."
else
    echo "An error occurred during extraction." >&2
    exit 1
fi
