#!/usr/bin/env bash

# validate inputs
USAGE="usage: ./get_tag.sh [registry] [repo] [region] [tag (optional)]"
[[ $# -lt 3 ]] && { echo "${USAGE}"; exit 1; }
[[ $# -gt 4 ]] && { echo "${USAGE}"; exit 1; }

registry=$(echo ${1} | cut -d'.' -f1)
repo=${2}
region=${3}

export AWS_RETRY_MODE=standard
export AWS_MAX_ATTEMPTS=10

# verify credentials exist
if [[ -z ${AWS_ACCESS_KEY_ID} ]]; then
  [[ -z ${AWS_PROFILE} ]] && { echo "ERR: Neither AWS_ACCESS_KEY_ID or AWS_PROFILE set"; exit 1; }
else
  [[ -z ${AWS_SECRET_ACCESS_KEY} ]] && { echo "ERR: AWS_ACCESS_KEY_ID provided but AWS_SECRET_ACCESS_KEY not set"; exit 1; }
fi

[[ -n ${4} ]] && { echo "::set-output name=version::${4}"; exit 0; }
ver=$(aws ecr describe-images \
  --region ${region} \
  --registry-id ${registry} \
  --output json \
  --repository-name ${repo} \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags' \
  | gsed -nr '/.{4}"([0-9]{14})",/p' \
  | gsed -e 's/"//g' -e 's/^[ \t]*//' -e 's/,//g'
)
echo "::set-output name=version::${ver}"