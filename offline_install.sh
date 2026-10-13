mkdir -p /repo/sdb && mount /dev/sdb /repo/sdb
mkdir -p /repo/img && mount -o loop /repo/sdb/arch-offline-packages.img /repo/img
curl -H "Cache-Control: no-cache, no-store" -fLO "https://raw.githubusercontent.com/Methusan105/archconfig/main/user_configuration_offline.json?$(date +%s)"
curl -H "Cache-Control: no-cache, no-store" -fLO "https://raw.githubusercontent.com/Methusan105/archconfig/main/user_credentials.json?$(date +%s)"
archinstall --config user_configuration_offline.json --creds user_credentials.json
