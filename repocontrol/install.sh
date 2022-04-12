#!/usr/bin/env bash
VER=$(curl -s https://api.github.com/repos/github/hub/releases/latest | grep tag_name | cut -d '"' -f 4)
echo -n "Installing Hub@${VER}..."
wget -q https://github.com/github/hub/releases/download/${VER}/hub-linux-amd64-${VER:1}.tgz
tar -xvf hub-linux-amd64-${VER:1}.tgz &>/dev/null
chmod +x ./hub-linux-amd64-${VER:1}/bin/hub
sudo mv ./hub-linux-amd64-${VER:1}/bin/hub /usr/bin/hub
echo "Done!"
sudo apt-get update -qq
VER=$(apt-cache madison git | head -n 1 | cut -d'|' -f2 | cut -d'-' -f1 | cut -d':' -f2)
echo -n "Installing git@latest..."
sudo apt install -y -qq git &>/dev/null
echo "Done!"