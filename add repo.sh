echo "=== Adding MethuRepo ==="

sudo sed -i '/^\[methurepos\]/,/^Server = /d' /etc/pacman.conf

printf '\n[methurepos]\nSigLevel = Optional\nServer = https://github.com/Methusan105/archconfig/releases/download/mr\n' \
| sudo tee -a /etc/pacman.conf >/dev/null

sudo pacman -Sy
