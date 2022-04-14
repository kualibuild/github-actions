#!/usr/bin/env bash
VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
echo -n "Installing Kubectl@${VER}..."
curl -sSLO https://storage.googleapis.com/kubernetes-release/release/${VER}/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Done!"

sudo apt-get update -qq
VER=$(apt-cache madison git | head -n 1 | cut -d'|' -f2 | cut -d'-' -f1 | cut -d':' -f2)
echo -n "Installing git@latest..."
sudo apt install -y -qq git jq &>/dev/null
echo "Done!"