#!/usr/bin/env bash 
# usage: ./close_api.sh [cluster_name] [region])

# validate inputs
USAGE="usage: ./close_api.sh [cluster_name] [region] [softfail]"
if [[ $# -lt 3 ]]; then
  echo "${USAGE}"
  exit 1
fi

VALID_REGIONS=("us-east-2" "us-east-1" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ca-central-1")
[[ "$1" =~ ^[a-zA-Z][-a-zA-Z0-9]*$ ]] || { echo "ERR: EKS cluster_name must be alphanumeric and start with a letter"; echo "${USAGE}"; exit 1; }
[[ "${VALID_REGIONS[@]}" =~ "${2}" ]] || { echo "ERR: region must be one of the following: ${VALID_REGIONS[@]}"; echo "${USAGE}"; exit 1; }
[[ "${3}" =~ ^true$|^false$ ]] || { echo "ERR: softfail must be set to either 'true' or 'false'"; echo "${USAGE}"; exit 1; }

# enable automatic retrylogic in awscli
export AWS_RETRY_MODE=standard
export AWS_MAX_ATTEMPTS=10

# verify credentials exist
if [[ -z ${AWS_ACCESS_KEY_ID} ]]; then
  [[ -z ${AWS_PROFILE} ]] && { echo "ERR: Neither AWS_ACCESS_KEY_ID or AWS_PROFILE set"; exit 1; }
else
  [[ -z ${AWS_SECRET_ACCESS_KEY} ]] && { echo "ERR: AWS_ACCESS_KEY_ID provided but AWS_SECRET_ACCESS_KEY not set"; exit 1; }
fi

# get ip address of the caller
IP_ADDR=$(curl -s ifconfig.me)

# validate cluster exists in region
CLUSTER=$(aws eks describe-cluster --name ${1} --region ${2} 2>/dev/null)
if [[ -z ${CLUSTER} ]]; then
  echo "ERR: Cluster ${1} does not exist in region ${2}"
  if [[ ${3} == "false" ]]; then
    exit 1
  else
    echo "WARN: Exiting success because softfail is enabled"
    exit 0
  fi
else
  echo "Removing API access for ${IP_ADDR}..."
  CIDRS=$(echo ${CLUSTER} | jq '.cluster.resourcesVpcConfig.publicAccessCidrs[]' | tr '\n' ',' | sed -e 's/,$//g' -e 's/\"//g' | sed -e "s|${IP_ADDR}/32||g" -e 's|,,|,|g')
  UPDATE_ID=$(aws eks update-cluster-config \
      --region ${2} \
      --name ${1} \
      --resources-vpc-config endpointPublicAccess=true,publicAccessCidrs="${CIDRS}",endpointPrivateAccess=true 2>/dev/null | jq -r '.update.id' 2>/dev/null)

  STATUS=$(aws eks describe-update --region ${2} --name ${1} --update-id ${UPDATE_ID} 2>/dev/null | jq -r '.update.status')
  while [[ ${STATUS} == "InProgress" ]]; do
    echo "Waiting for update to complete..."
    sleep 5
    STATUS=$(aws eks describe-update --region ${2} --name ${1} --update-id ${UPDATE_ID} 2>/dev/null | jq -r '.update.status')
  done

  if [[ ${STATUS} != "Successful" ]]; then
    echo "Failed to update cluster config"
  else
    echo "Updated cluster config"
  fi
fi
