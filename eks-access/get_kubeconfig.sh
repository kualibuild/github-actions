#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved

# validate inputs
USAGE="usage: ./get_kubeconfig.sh [cluster_name] [region] [softfail]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

VALID_REGIONS=("us-east-2" "us-east-1" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ca-central-1")
[[ "${1}" =~ ^[a-zA-Z][-a-zA-Z0-9]*$ ]] || { echo "ERR: EKS cluster_name must be alphanumeric and start with a letter"; echo "${USAGE}"; exit 1; }
[[ "${VALID_REGIONS[@]}" =~ "${2}" ]] || { echo "ERR: region must be one of the following: ${VALID_REGIONS[@]}"; echo "${USAGE}"; exit 1; }
[[ "${3}" =~ ^true$|^false$ ]] || { echo "ERR: softfail must be set to either 'true' or 'false'"; echo "${USAGE}"; exit 1; }

# enable automatic retrylogic in awscli
export AWS_RETRY_MODE=standard
export AWS_MAX_ATTEMPTS=10

# get kubeconfig for eks
if aws eks --region ${2} update-kubeconfig --name ${1} --alias ${1}; then
  kubectl config set-context --current --namespace=argocd
  echo "::set-output name=softfailed::false"
else
  if [[ ${3} == "false" ]]; then 
    echo "ERR: aws eks update-kubeconfig failed"
    exit 1
  else
    echo "WARN: Exiting success because softfail is enabled"
    echo "::set-output name=softfailed::true"
    exit 0
  fi
fi
