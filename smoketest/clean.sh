#!/usr/bin/env bash

[[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }

[[ -d $(echo ${GITHUB_REPO} | cut -d'/' -f2) ]] && rm -rf $(echo ${GITHUB_REPO} | cut -d'/' -f2)