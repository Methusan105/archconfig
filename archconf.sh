#!/bin/bash
set -e

curl -H "Cache-Control: no-cache, no-store" -fLO "https://raw.githubusercontent.com/Methusan105/archconfig/main/user_configuration.json?$(date +%s)"
curl -H "Cache-Control: no-cache, no-store" -fLO "https://raw.githubusercontent.com/Methusan105/archconfig/main/user_credentials.json?$(date +%s)"

archinstall --config user_configuration.json --creds user_credentials.json
