#!/usr/bin/env bash
export DEPLOY_START_TIME=$(date +%s)

# validate inputs
USAGE="usage: ./run.sh [branch] [namespace] [cluster_name] [version] [noverify]"
if [[ $# -lt 5 ]]; then
  echo "${USAGE}"
  exit 1
fi
bool=("true" "false")
noverify=${5}
[[ ! ${bool[@]} =~ ${noverify} ]] && { echo "ERR: noverify must be 'true' or 'false'"; exit 1; }

retry=0
while [[ ${retry} -le 5 ]]; do
  kubectl version --short || echo "ERR: unable to connect to kubernetes cluster" && break
  ((retry++))
  echo "Retrying in 30 seconds... (count: ${retry})"
  sleep 30
done
kubectl get ns ${2} &>/dev/null || { echo "ERR: namespace \'${2}\' does not exist"; exit 1; }
kubectl get ns argocd &>/dev/null || { echo "ERR: namespace 'argocd' does not exist"; exit 1; }
kubectl config set-context --current --namespace=argocd || { echo "ERR: unable to set context to 'argocd' namespace"; exit 1; }

# ${1} required vars exist
[[ -z ${SERVICE} ]] && { echo "ERR: SERVICE not set"; exit 1; }
[[ -z ${SERVICE_NAME} ]] && { echo "ERR: SERVICE not set"; exit 1; }
[[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }
[[ -z ${GITHUB_TOKEN} ]] && { echo "ERR: GITHUB_TOKEN not set"; exit 1; }
[[ -z ${GITHUB_USER} ]] && { echo "ERR: GITHUB_USER not set"; exit 1; }
REPOSTRING="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}"

# define functions

clone() {
  echo "Cloning Repository: ${1}"
  git clone ${2}
  cd $(echo ${GITHUB_REPO} | cut -d'/' -f2)/overlays/
  git config user.name "Cameron Larsen"
  git config user.email "cameron@larsenfam.org"
}

mkbranch() {
  branch=${1}
  cluster=${2}
  tag=${3}
  name="update-${branch}-${cluster}-${tag}"
  if [[ ! "main master" =~ ${branch} ]]; then
    echo "Creating branch: ${branch}"
    git switch -c ${branch} origin/${branch}
    git checkout -b ${branch}
  fi
  git checkout -b ${name}
  sed -i "s/^    newTag: .*$/    newTag: \'${tag}\'/" ./*/*/kustomization.yaml
  # check if commit is needed
  git add . -A &>/dev/null
  changes=$(git status -s)
  if [ -n "${changes}" ]; then 
    git commit -m "Updated image tag to ${tag}"
    echo "Pushing to remote: ${name}"
    git push --set-upstream origin ${name} &>/dev/null
  fi
}

forkbranch() {
  branch=${1}
  cluster=${2}
  tag=${3}
  name="update-${branch}-${cluster}-${tag}"
  # validate remote branch exists
  [[ $(git branch -r | grep "origin/verify") ]] || { echo "ERR: 'verify' branch does not exist"; exit 1; }
  # checkout remote branch
  git switch -c verify origin/verify
  git switch ${branch}
  git checkout -b ${name}
  sync
  # checkout verify branch paths that we want push into master
  for i in $(ls -d */ | grep verify); do
    git checkout verify -- ${i}
  done
  for i in $(ls -d */ | grep ${cluster}); do
    git checkout verify -- ${i}
  done
  # check if commit is needed
  git add . -A &>/dev/null
  changes=$(git status -s)
  if [ -n "${changes}" ]; then 
    git commit -am "Updated image tag to ${tag}"
    echo "Pushing to remote: ${name}"
    git push --set-upstream origin ${name} &>/dev/null
  fi
}

mkpr() {
  branch=${1}
  tag=${2}
  local PR=$(hub pull-request -p -b ${branch} -m "Updated image tag to ${tag}" | grep github.com | rev | cut -d'/' -f1 | rev)
  echo ${PR}
}

prstatus() {
  # deal with status checks
  count=0
  until [[ $(hub ci-status) == "pending" ]]; do 
    ((count+=1))
    [[ ${count} -gt 1 ]] && echo "No status checks required for this PR" && break
    echo "Waiting to see if status checks are required for this PR"
    sleep 5
  done
  count=0
  while [[ $(hub ci-status) == "pending" ]]; do 
    [[ ${count} -eq 0 ]] && echo "Waiting for required status checks to pass before merge"
    ((count+=1))
    sleep 1
  done
  case $(hub ci-status) in
    success)
      echo "Status checks passed"
      ;;
    failure)
      echo "Required status checks did not pass. For more information, please see $(hub ci-status --verbose | awk '{print $3}')"; exit 1
      ;;
  esac
}

mergewait() {
  REPO=${1}
  PR=${2}
  # attempt merge
  echo "  * $(hub api -XPUT "repos/${REPO}/pulls/${PR}/merge" | jq  -r '.message')"
  # wait for merge to complete
  until [[ $(hub pr list | grep -c "#${PR}") == 0 ]]; do
    echo "  * PR still open, waiting for merge to complete. Checking again in 30s"
    hub api -XPUT "repos/${REPO}/pulls/${PR}/merge" &>/dev/null
    sleep 30
  done
  echo "  * PR #${PR} Merged."
}

deploywait() {
  ns=${1}
  tag=${2}
  targets=$(kubectl -n ${ns} get deploy | grep ${SERVICE} | awk '{print $1}')
  for tar in ${targets}; do
    echo "Waiting for rollout to begin for deployment/${tar}."
    count=0
    until [[ $(kubectl -n ${ns} get deploy ${tar} -o jsonpath='{.spec.template.spec.containers[*].image}' | grep -o ${tag}) == "${tag}" ]]; do
      ((count+=0))
      [[ ${count} -ge 10 ]] && { echo "  * Rollout has yet to begin for deployment/${tar}. Aborting but leaving branch for investigation"; exit 1; }
      echo "  * Rollout has yet to begin for deployment/${tar}. Checking again in 30s"
      sleep 30
    done
  done
}

# clone repo and edit files
clone ${GITHUB_REPO} ${REPOSTRING}

if [[ "${1}" == "verify" || "${noverify}" == "true" ]]; then
  mkbranch ${1} ${3} ${4}
elif [[ ${noverify} == "false" ]]; then
  forkbranch ${1} ${3} ${4}
else
  echo "WARN: set to 'true' but target branch is set to verify. Unable to proceed."
fi

# create PR
if [ -n "${changes}" ]; then
  export GITHUB_PR=$(mkpr ${1} ${4})
  echo "Created PR: ${GITHUB_PR}"

  # deal with status checks
  prstatus

  # merge PR
  mergewait ${GITHUB_REPO} ${GITHUB_PR}

  # sync argo
  argocd app sync ${SERVICE} &>/dev/null

  # wait for argo to increment the version on the deploy which signals the start of the rollout
  deploywait ${2} ${4}

  # watch rollout status
  kubectl -n ${2} rollout status deploy/${SERVICE}

  # add deploy marker to honeycomb
  [[ ! -z ${HONEYCOMB_KEY} ]] || curl https://api.honeycomb.io/1/markers/builder \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Honeycomb-Team: ${HONEYCOMB_KEY}" \
    -d "{\"message\":\"Deploy ${SERVICE_NAME}-${1} ${4}\", \"type\":\"deploy-${SERVICE_NAME}-${1}\", \"start_time\": ${DEPLOY_START_TIME}, \"end_time\": $(date +%s), \"url\": \"https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}\"}"
else
  echo "No changes to commit, working branch is clean."
fi