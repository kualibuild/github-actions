#!/usr/bin/env bash

[[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }
[[ -z ${GITHUB_TOKEN} ]] && { echo "ERR: GITHUB_TOKEN not set"; exit 1; }
[[ -z ${GITHUB_USER} ]] && { echo "ERR: GITHUB_USER not set"; exit 1; }

# clone repo and edit files
echo "Cloning Repository: ${GITHUB_REPO}"
git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO} || { echo "ERR: failed to clone repo"; exit 1; }
cd $(echo ${GITHUB_REPO} | cut -d'/' -f2)/
git config user.name "Cameron Larsen"
git config user.email "cameron@larsenfam.org"