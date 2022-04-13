#!/usr/bin/env bash

# validate inputs
USAGE="usage: ./get_kubeconfig.sh [true|false] [cluster_name] [region|statefile]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

VALID_REGIONS=("us-east-2" "us-east-1" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ca-central-1")
[[ "$1" == "true" || "$1" == "false" ]] || { echo "ERR: First argument must be true or false"; echo "${USAGE}"; exit 1; }
if [[ "$1" == "true" ]]; then
  [[ "$2" =~ ^[a-zA-Z][-a-zA-Z0-9]*$ ]] || { echo "ERR: EKS cluster_name must be alphanumeric and start with a letter"; echo "${USAGE}"; exit 1; }
  [[ "${VALID_REGIONS[@]}" =~ "${3}" ]] || { echo "ERR: region must be one of the following: ${VALID_REGIONS[@]}"; echo "${USAGE}"; exit 1; }
else
  [[ "$2" =~ ^([a-z0-9\-]*\.){0,2}k8s.local$ ]] || { echo "ERR: KOPS cluster_name must be FQDN ending in k8s.local"; echo "${USAGE}"; exit 1; }
  [[ "$3" =~ ^s3://.*$ ]] || { echo "ERR: statefile should be an s3 address"; echo "${USAGE}"; exit 1; }
fi

# enable automatic retrylogic in awscli
export AWS_RETRY_MODE=standard
export AWS_MAX_ATTEMPTS=10

# get kubeconfig for kops
if [[ "$1" == "false" ]]; then
  kops export kubecfg --admin --name ${2} --state ${3} || { echo "ERR: kops export kubecfg failed"; exit 1; }
  # configure kubectl 
  kubectl config set-context platform_verify --namespace=verify --cluster=${2} --user=${2}
  kubectl config use-context platform_verify
fi

# get kubeconfig for eks
if [[ "$1" == "true" ]]; then
  aws eks --region ${3} update-kubeconfig --name ${2} --alias ${2} || { echo "ERR: aws eks update-kubeconfig failed"; exit 1; }
fi