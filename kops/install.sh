#!/usr/bin/env bash
VER=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)
echo -n "Installing Kops@${VER}..."
wget -qO kops https://github.com/kubernetes/kops/releases/download/${VER}/kops-linux-amd64
chmod +x ./kops
sudo mv ./kops /usr/local/bin/
echo "Done!"
VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
echo -n "Installing Kubectl@${VER}..."
curl -sSLO https://storage.googleapis.com/kubernetes-release/release/${VER}/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Done!"