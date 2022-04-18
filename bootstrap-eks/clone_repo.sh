#!/usr/bin/env bash

# verify required env vars exist
[[ -z ${GITHUB_TOKEN} ]] && { echo "ERR: GITHUB_TOKEN not set"; exit 1; }
[[ -z ${GITHUB_USER} ]] && { echo "ERR: GITHUB_USER not set"; exit 1; }

git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/KualiCo/k8s-apps.git
