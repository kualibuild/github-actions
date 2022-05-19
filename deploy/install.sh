#!/usr/bin/env bash
#VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
VER='v1.23.5'
echo -n "Installing Kubectl@${VER}..."
curl -sSLO https://storage.googleapis.com/kubernetes-release/release/${VER}/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
echo "Done!"

if [[ $1 == "false" ]]; then
  VER=$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)
  echo -n "Installing Kops@${VER}..."
  wget -qO kops https://github.com/kubernetes/kops/releases/download/${VER}/kops-linux-amd64
  chmod +x ./kops
  sudo mv ./kops /usr/local/bin/
  echo "Done!"
fi

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
sudo apt install -y -qq git jq &>/dev/null
echo "Done!"

echo -n "Installing ArgoCD@latest..."
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
echo "Done!"