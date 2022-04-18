#!/usr/bin/env bash
export DEPLOY_START_TIME=$(date +%s)

# validate inputs
USAGE="usage: ./run.sh [branch] [namespace] [cluster_name] [version]"
if [[ $# -lt 4 ]]; then
  echo "${USAGE}"
  exit 1
fi

kubectl get ns ${2} &>/dev/null || { echo "ERR: namespace ${2} does not exist"; exit 1; }
kubectl config set-context --current --namespace=${2}

# ${1} required vars exist
[[ -z ${SERVICE} ]] && { echo "ERR: SERVICE not set"; exit 1; }
[[ -z ${SERVICE_NAME} ]] && { echo "ERR: SERVICE not set"; exit 1; }
[[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }
[[ -z ${GITHUB_TOKEN} ]] && { echo "ERR: GITHUB_TOKEN not set"; exit 1; }
[[ -z ${GITHUB_USER} ]] && { echo "ERR: GITHUB_USER not set"; exit 1; }

# clone repo and edit files
echo "Cloning Repository: ${GITHUB_REPO}"
git clone https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}
cd $(echo ${GITHUB_REPO} | cut -d'/' -f2)/overlays/
git config user.name "Cameron Larsen"
git config user.email "cameron@larsenfam.org"

if [[ "$1" == "verify" ]]; then
  git switch -c ${1} origin/${1}
  git checkout -b update-${1}-${4}
  sed -i "s/^    newTag: .*$/    newTag: \'${4}\'/" ./*/app/kustomization.yaml
  # check if commit is needed
  git add . -A &>/dev/null
  changes=$(git status -s)
  if [ -n "${changes}" ]; then 
    git commit -m "Updated image tag to ${4}"
    echo "Pushing to remote: update-${1}-${4}"
    git push --set-upstream origin update-${1}-${4} &>/dev/null
  fi
else
  git switch -c verify origin/verify
  git switch ${1}
  git checkout -b update-prod-${3}-${4}
  for i in $(ls -d */ | grep verify); do
    git checkout verify -- ${i}
  done
  for i in $(ls -d */ | grep ${3}); do
    git checkout verify -- ${i}
  done
  # check if commit is needed
  git add . -A &>/dev/null
  changes=$(git status -s)
  if [ -n "${changes}" ]; then 
    git commit -am "Updated image tag to ${4}"
    echo "Pushing to remote: update-prod-${3}-${4}"
    git push --set-upstream origin update-prod-${4} &>/dev/null
  fi
fi

# create PR
if [ -n "${changes}" ]; then
  export GITHUB_PR=$(hub pull-request -p -b ${1} -m "Updated image tag to ${4}"| rev | cut -d'/' -f1 | rev || { echo "ERR: PR not created"; exit 1; })
  echo "Created PR: ${GITHUB_PR}"

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

  # merge PR
  hub api -XPUT "repos/${GITHUB_REPO}/pulls/${GITHUB_PR}/merge" &>/dev/null

  # wait for merge to complete
  until [[ $(hub pr list | grep -c update-${1}-${4}) == 0 ]]; do
    echo "  * waiting for merge to complete. Checking again in 30s"
    sleep 30
  done
  echo "  * Merged."

  # wait for argo to increment the version on the deploy which signals the start of the rollout
  echo "Waiting for rollout to begin for deployment/${SERVICE}."
  count=0
  until [[ $(kubectl -n ${2} get deploy ${SERVICE} -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d':' -f2) == "${4}" ]]; do
    ((count+=0))
    [[ ${count} -ge 10 ]] && echo "  * Rollout has yet to begin for deployment/${SERVICE}. Aborting."
    echo "  * Rollout has yet to begin for deployment/${SERVICE}. Checking again in 30s"
    sleep 30
  done

  # Delete the branch now that we are done with it
  git switch ${1}
  git branch -d update-${1}-${4}
  git push origin --delete update-${1}-${4}

  kubectl -n ${2} rollout status deploy/$SERVICE

  [[ ${count} -ge 10 ]] && exit 1

  # add deploy marker to honeycomb
  [[ ! -z ${HONEYCOMB_KEY} ]] || curl https://api.honeycomb.io/1/markers/builder \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Honeycomb-Team: ${HONEYCOMB_KEY}" \
    -d "{\"message\":\"Deploy ${SERVICE_NAME}-${1} ${4}\", \"type\":\"deploy-${SERVICE_NAME}-${1}\", \"start_time\": ${DEPLOY_START_TIME}, \"end_time\": $(date +%s), \"url\": \"https://github.com/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}\"}"
else
  echo "No changes to commit"
fi