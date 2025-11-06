#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved

if ! hash hub 2>/dev/null; then
  VER=$(curl -s https://api.github.com/repositories/401025/releases/latest | grep tag_name | cut -d '"' -f 4)
  echo -n "Installing Hub@${VER}..."
  wget -q https://github.com/github/hub/releases/download/${VER}/hub-linux-amd64-${VER:1}.tgz
  tar -xvf hub-linux-amd64-${VER:1}.tgz &>/dev/null
  chmod +x ./hub-linux-amd64-${VER:1}/bin/hub
  sudo mv ./hub-linux-amd64-${VER:1}/bin/hub /usr/bin/hub
echo "Done!"
else
  echo "Hub is already installed at $(which hub)"
fi
