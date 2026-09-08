#!/bin/bash

# Ensure required commands are installed
for cmd in zenity curl tar sudo; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed." >&2
        exit 1
    fi
done

# Ask user for the first URL via GUI
FIRST_URL=$(zenity --entry \
    --title="Timeshift Restore" \
    --text="Enter the URL of the FIRST split part (ending in .001 or .aa):" \
    --entry-text="https://github.com/Methusan105/Personal/releases/download/ALB/timeshift-backup.tar.gz.001")

if [ -z "$FIRST_URL" ]; then
    echo "No URL provided. Exiting."
    exit 0
fi

# Detect extension type (.001 numeric vs .aa alphabetic)
if [[ "$FIRST_URL" =~ \.001$ ]]; prefix="${FIRST_URL%.001}"
    # Generate sequential numeric URLs (.001, .002, ...)
    URL_LIST=()
    i=1
    while true; do
        part_url=$(printf "%s.%03d" "$prefix" "$i")
        # Check if the part URL exists on the server without downloading it
        if curl --output /dev/null --silent --head --fail "$part_url"; then
            URL_LIST+=("$part_url")
            ((i++))
        else
            break
        fi
    done
else
    # Fallback: Just use the single URL provided if it doesn't end in .001
    URL_LIST=("$FIRST_URL")
fi

echo "Found ${#URL_LIST[@]} archive part(s) to stream:"
printf " - %s\n" "${URL_LIST[@]}"

# Stream all parts in sequence directly into tar
curl -sL "${URL_LIST[@]}" | sudo tar -xzvf - -C /timeshift/snapshots/

if [ ${PIPESTATUS[0]} -eq 0 ] && [ ${PIPESTATUS[1]} -eq 0 ]; then
    echo "Extraction completed successfully."
else
    echo "An error occurred during extraction." >&2
    exit 1
fi
