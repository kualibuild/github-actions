#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved

[[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }

[[ -d $(echo ${GITHUB_REPO} | cut -d'/' -f2) ]] && rm -rf $(echo ${GITHUB_REPO} | cut -d'/' -f2)