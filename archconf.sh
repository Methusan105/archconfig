#!/bin/bash
set -e

curl -fLO https://raw.githubusercontent.com/Methusan105/archconfig/main/user_configuration.json
curl -fLO https://raw.githubusercontent.com/Methusan105/archconfig/main/user_credentials.json

archinstall --config user_configuration.json --creds user_credentials.json
