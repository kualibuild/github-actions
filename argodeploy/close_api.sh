#!/usr/bin/env bash 
# usage: ./close_api.sh [true|false] [cluster_name] [region] [original_ips|security_group_id])

# validate inputs
USAGE="usage: ./close_api.sh [true|false] [cluster_name] [region] [original_ips|security_group_id]"
if [[ $# -lt 4 ]]; then
  echo "${USAGE}"
  exit 1
fi

IP_REGEX='^(([0-9]{1,3}.){3}[0-9]{1,3}\/[0-9]{1,2},*){1,}$'

VALID_REGIONS=("us-east-2" "us-east-1" "us-west-1" "us-west-2" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ca-central-1")
[[ "$1" == "true" || "$1" == "false" ]] || { echo "ERR: First argument must be true or false"; echo "${USAGE}"; exit 1; }
if [[ "$1" == "true" ]]; then
  [[ "$2" =~ ^[a-zA-Z][-a-zA-Z0-9]*$ ]] || { echo "ERR: EKS cluster_name must be alphanumeric and start with a letter"; echo "${USAGE}"; exit 1; }
  [[ "$4" =~ ${IP_REGEX} ]] || { echo "ERR: original_ips should be one or more ip addresses in CIDR notation comma delimited"; echo "${USAGE}"; exit 1; }
else
  [[ "$2" =~ ^([a-z0-9\-]*\.){0,2}k8s.local$ ]] || { echo "ERR: KOPS cluster_name must be FQDN ending in k8s.local"; echo "${USAGE}"; exit 1; }
  [[ "$4" =~ ^sg-[a-zA-Z0-9]{17}$ ]] || { echo "ERR: security_group_id should be an 18 charachter string matching \"^sg-[a-zA-Z0-9]{17}$\""; echo "${USAGE}"; exit 1; }
fi
[[ "${VALID_REGIONS[@]}" =~ "${3}" ]] || { echo "ERR: region must be one of the following: ${VALID_REGIONS[@]}"; echo "${USAGE}"; exit 1; }

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

if [[ $1 == "false" ]]; then
  # check if sg exists
  if ! aws ec2 describe-security-groups --region ${3} --group-ids ${4} &>/dev/null; then
    echo "ERR: security_group_id ${4} does not exist in region ${3}"
    exit 1
  fi

  echo "Removing API access for ${IP_ADDR}..."

  # close sg
  if ! aws ec2 revoke-security-group-ingress --region ${3} --group-id ${4} --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=${IP_ADDR}/32,Description='temp api access for ci'}]" &>/dev/null; then
    echo "ERR: failed to update sg ${4} in region ${3}"
  else
    echo "Updated sg ${4} in region ${3}"
  fi
fi

if [[ $1 == "true" ]]; then
  # validate cluster exists in region
  CLUSTER=$(aws eks describe-cluster --name ${2} --region ${3} 2>/dev/null)
  [[ -z ${CLUSTER} ]] && { echo "ERR: Cluster ${2} does not exist in region ${3}"; exit 1; }

  echo "Removing API access for ${IP_ADDR}..."
  UPDATE_ID=$(aws eks update-cluster-config \
      --region ${3} \
      --name ${2} \
      --resources-vpc-config endpointPublicAccess=true,publicAccessCidrs="${4}",endpointPrivateAccess=true | jq -r '.update.id')

   STATUS=$(aws eks describe-update --region ${3} --name ${2} --update-id ${UPDATE_ID} | jq -r '.update.status')
  while [[ ${STATUS} == "InProgress" ]]; do
    echo "Waiting for update to complete..."
    sleep 5
    STATUS=$(aws eks describe-update --region ${3} --name ${2} --update-id ${UPDATE_ID} | jq -r '.update.status')
  done

  if [[ ${STATUS} != "Successful" ]]; then
    echo "Failed to update cluster config"
  else
    echo "Updated cluster config"
  fi
fi