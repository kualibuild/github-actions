#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved
VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
echo -n "Installing Kubectl@${VER}..."
curl -sSLO https://storage.googleapis.com/kubernetes-release/release/${VER}/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Done!"

echo -n "Installing git@latest..."
sudo apt-get update -qq
sudo apt install -y -qq git timelimit jq &>/dev/null
echo "Done!"

VER=$(curl -s https://api.github.com/repositories/401025/releases/latest | grep tag_name | cut -d '"' -f 4)
echo -n "Installing Hub@${VER}..."
wget -q https://github.com/github/hub/releases/download/${VER}/hub-linux-amd64-${VER:1}.tgz
tar -xvf hub-linux-amd64-${VER:1}.tgz &>/dev/null
chmod +x ./hub-linux-amd64-${VER:1}/bin/hub
sudo mv ./hub-linux-amd64-${VER:1}/bin/hub /usr/bin/hub
echo "Done!"

get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

VER=$(get_latest_release vmware-tanzu/velero)
echo -n "Installing Velero@${VER}..."
curl -o velero.tar.gz -sSLO https://github.com/vmware-tanzu/velero/releases/download/${VER}/velero-${VER}-linux-amd64.tar.gz
tar -xzf velero.tar.gz -C /usr/local/bin --strip-components=1 velero-${VER}-linux-amd64/velero
echo "Done!"

echo -n "Installing ArgoCD@latest..."
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
echo "Done!"
