#!/usr/bin/env bash
export DEPLOY_START_TIME=$(date +%s)

# validate inputs
USAGE="usage: ./run.sh [cluster_name] [version]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

# check k8s connectivity
kubectl version --short &>/dev/null || { echo -e "\e[31mERR: unable to connect to kubernetes cluster\e[0m"; exit 1; }
kubectl get ns argocd &>/dev/null || { echo -e "\e[31mERR: namespace 'argocd' does not exist\e[0m"; exit 1; }
kubectl config set-context --current --namespace=argocd &>/dev/null || { echo -e "\e[31mERR: unable to set context to 'argocd' namespace\e[0m"; exit 1; }

# check required env vars exist
[[ -z ${GITHUB_REPO} ]] && { echo -e "\e[31mERR: GITHUB_REPO not set\e[0m"; exit 1; }
[[ -z ${GITHUB_TOKEN} ]] && { echo -e "\e[31mERR: GITHUB_TOKEN not set\e[0m"; exit 1; }
[[ -z ${GITHUB_USER} ]] && { echo -e "\e[31mERR: GITHUB_USER not set\e[0m"; exit 1; }


# define functions
clone() {
  [[ $# -ne 0 ]] && { echo -e "\e[31mERR: clone() requires exactly 0 arguments\e[0m"; exit 1; }
  local addr="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_REPO}"
  local dpath="$(echo ${GITHUB_REPO} | cut -d'/' -f2)"
  if [[ -d ${dpath} ]]; then
    echo "WARN: ${dpath} already exists"
    cd ${dpath}
    local branch=$(git remote show origin | grep 'HEAD branch:' | awk '{print $3}')
    local cur=$(git branch -l | grep \* | awk '{print $2}')
    [[ -z ${branch} ]] && { echo -e "\e[31mERR: unable to determine HEAD branch\e[0m"; exit 1; }
    [[ -z ${cur} ]] && { echo -e "\e[31mERR: unable to determine current branch\e[0m"; exit 1; }
    if [[ ${cur} != ${branch} ]]; then
      echo "WARN: ${cur} != ${branch}"
      git switch ${branch}
    fi
  else
    echo -n "Cloning Repository: ${GITHUB_REPO}..."
    git clone ${addr} &>/dev/null || { echo -e "\e[31mfail!\e[0m"; echo -e "\e[31mERR: unable to clone repository\e[0m"; exit 1; }
    echo "done!"
    [[ -d ${dpath} ]] || { echo -e "\e[31mERR: directory \'${dpath}\' does not exist\e[0m"; exit 1; }
    cd ${dpath} || { echo -e "\e[31mERR: unable to cd to \'${dpath}\'\e[0m"; exit 1; }
    echo "Changed directory to: $(pwd)"
  fi
  git config user.name "Cameron Larsen"
  git config user.email "cameron@larsenfam.org"
}

mkbranch() {
  [[ $# -ne 2 ]] && { echo -e "\e[31mERR: mkbranch() requires exactly 2 arguments\e[0m"; exit 1; }
  local cluster=${1}
  local tag=${2}
  local name="update-${cluster}-${tag}"
  local dpath="overlays/${cluster}"
  [[ -d ${dpath} ]] || { echo -e "\e[31mERR: directory \'${cluster}\' does not exist\e[0m"; exit 1; }
  if [[ -f ${dpath}/kustomization.yaml ]]; then
    local fpath="${dpath}/*/kustomization.yaml"
  elif [[ -f ${dpath}/kustomization.yml ]]; then
    local fpath="${dpath}/*/kustomization.yml"
  elif [[ -f ${dpath}/Kustomization ]]; then
    local fpath="${dpath}/*/Kustomization"
  else
    echo -e "\e[31mERR: directory \'${dpath}\' does not appear to be a valid Kustomize directory"
    exit 1
  fi
  local exists=$(git branch -l ${name})
  [[ -n ${exists} ]] && { echo "WARN: branch '${name}' already exists"; cleanup ${cluster} ${tag}; }
  git checkout -b ${name} &>/dev/null
  sed -i "s/^    newTag: .*$/    newTag: \"${tag}\"/" ${fpath}
  # check if commit is needed
  git add . -A &>/dev/null
  local changes=$(git status -s)
  if [ -n "${changes}" ]; then 
    git commit -m "Updated image tag to ${tag}" &>/dev/null
    echo -n "Pushing to remote: ${name}..."
    git push --set-upstream origin ${name} &>/dev/null || { echo -e "\e[31mfail!\e[0m"; echo -e "\e[31mERR: unable to push branch to remote\e[0m"; exit 1; }
    echo "done!"
    export NEED_PR=true
  else
    echo "No changes to commit"
    export NEED_PR=false
  fi
}

checkpr() {
  [[ $# -ne 0 ]] && { echo -e "\e[31mERR: checkpr() requires exactly 0 arguments\e[0m"; exit 1; }
  # deal with status checks
  local count=0
  until [[ $(hub ci-status) == "pending" ]]; do 
    ((count+=1))
    [[ ${count} -gt 1 ]] && break
    echo -n "  * Waiting to see if status checks are required for this PR..."
    sleep 5
  done
  echo "done!"
  [[ ${count} -gt 1 ]] && echo "No status checks required for this PR"
  local count=0
  while [[ $(hub ci-status) == "pending" ]]; do 
    [[ ${count} -eq 0 ]] && echo -n "  * Waiting for required status checks to pass before merge..."
    ((count+=1))
    sleep 1
  done
  case $(hub ci-status) in
    success)
      echo "done!"
      ;;
    failure)
      echo -e "\e[31mfail!\e[0m"
      echo -e "\e[31mERR: Required status checks did not pass. For more information, please see $(hub ci-status --verbose | awk '{print $3}')"; exit 1
      ;;
  esac
}

mkpr() {
  [[ $# -ne 1 ]] && { echo -e "\e[31mERR: mkpr() requires exactly 1 argument\e[0m"; exit 1; }
  local tag=${1}
  local branch=$(git remote show origin | grep 'HEAD branch:' | awk '{print $3}')
  local cur=$(git branch -l | grep \* | awk '{print $2}')
  [[ -z ${branch} ]] && { echo -e "\e[31mERR: unable to determine HEAD branch\e[0m"; exit 1; }
  [[ -z ${cur} ]] && { echo -e "\e[31mERR: unable to determine current branch\e[0m"; exit 1; }
  until [[ $(git branch -r | grep origin/${cur}) ]]; do
    sleep 5
  done
  local pr=$(hub pull-request -p -b ${branch} -m "Updated image tag to ${tag}" | grep ${GITHUB_REPO} | rev | cut -d'/' -f1 | rev)
  [[ -z ${pr} ]] && { echo -e "\e[31mERR: unable to create pull request\e[0m"; exit 1; }
  echo ${pr}
}

mergepr() {
  [[ $# -ne 0 ]] && { echo -e "\e[31mERR: mergepr() requires exactly 0 arguments\e[0m"; exit 1; }
  [[ -z ${PR} ]] && { echo -e "\e[31mERR: PR not set\e[0m"; exit 1; }
  # attempt merge
  echo "  * $(hub api -XPUT "repos/${GITHUB_REPO}/pulls/${PR}/merge" | jq  -r '.message')"
  # wait for merge to complete
  until [[ $(hub pr list | grep -c "#${PR}") == 0 ]]; do
    echo "  * PR still open, waiting for merge to complete. Checking again in 30s"
    hub api -XPUT "repos/${REPO}/pulls/${PR}/merge" &>/dev/null
    sleep 30
  done
  echo "PR #${PR} Merged"
}

deployinfo() {
  [[ $# -ne 1 ]] && { echo -e "\e[31mERR: deployinfo() requires exactly 1 argument\e[0m"; exit 1; }
  local cluster=${1}
  local dpath="overlays/${cluster}"
  [[ -d ${dpath} ]] || { echo -e "\e[31mERR: directory \'${1}\' does not exist\e[0m"; exit 1; }
  [[ -f ${dpath}/kustomization.yaml || -f ${dpath}/kustomization.yml || -f ${dpath}/Kustomization ]] || { echo -e "\e[31mERR: directory \'${dpath}\' does not appear to be a valid Kustomize directory\e[0m"; exit 1; }
  local raw=$(kustomize build ${dpath})
  export RESOURCES=$(echo "${raw}" | kubectl apply --dry-run=client -f - | cut -d' ' -f1)
  export NS=$(echo "${raw}" | grep -A 20 'kind: Deployment' |  grep 'namespace' | sort | uniq -c | sort -rn | head | awk '{print $3}')
  export ARGO=$(echo "${raw}" | grep -A 20 'kind: Application' |  grep 'name:' | awk '{print $2}')
  local deploy=$(echo "${RESOURCES}" | grep "deployment.apps/")
  local statefulset=$(echo "${RESOURCES}" | grep "statefulset.apps/")
  local pod=$(echo "${RESOURCES}" | grep "pod/")
  local daemonset=$(echo "${RESOURCES}" | grep "daemonset.apps/")
  export TARGETS="${deploy} ${statefulset} ${pod} ${daemonset}"
}

deploywait() {
  [[ $# -ne 2 ]] && { echo -e "\e[31mERR: deploywait() requires exactly 2 arguments\e[0m"; exit 1; }
  local cluster=${1}
  local tag=${2}
  deployinfo ${cluster}
  # sync argo
  argocd app sync ${ARGO} &>/dev/null
  local max=10
  local timeout=$((${max}*30))
  for tar in ${TARGETS}; do
    echo -n "Waiting for rollout to begin for ${tar} (timeout ${timeout}s)..."
    local count=0
    # add if to catch pods
    if [[ ${tar} =~ 'pod/' ]]; then
      local jsonpath="'{.spec.containers[*].image}'"
    else
      local jsonpath="'{.spec.template.spec.containers[*].image}'"
    fi
    until [[ $(kubectl -n ${NS} get ${tar} -o jsonpath=${jsonpath} | grep -o ${tag}) == "${tag}" ]]; do
      ((count+=1))
      [[ ${count} -ge ${max} ]] && { echo -e "\e[31mfail!\e[0m"; echo -e "\e[31mERR: Rollout never began for ${tar}\e[0m"; exit 1; }
      sleep 30
    done && echo "done!"
  done
  # watch rollout status
  for tar in ${TARGETS}; do
    kubectl -n ${NS} rollout status ${tar} || { echo -e "\e[31mfail!\e[0m"; echo -e "\e[31mERR: Rollout failed for ${tar}\e[0m"; exit 1; }
    # do we want automated rollback, or to leave failed pods for investigation?
  done
}

cleanup() {
  [[ $# -ne 2 ]] && { echo -e "\e[31mERR: cleanup() requires exactly 2 arguments\e[0m"; exit 1; }
  echo -n "Cleaning up..."
  local cluster=${1}
  local tag=${2}
  local branch=$(git remote show origin | grep 'HEAD branch:' | awk '{print $3}')
  [[ -z ${branch} ]] && { echo -e "\e[31mfail!\e[0m"; echo -e "\e[31mERR: unable to determine HEAD branch\e[0m"; exit 1; }
  local name="update-${cluster}-${tag}"
  git switch ${branch} &>/dev/null
  git push origin --delete ${name} &>/dev/null
  git branch -d ${name} &>/dev/null
  echo "done!"
}

# clone repo and edit files
clone
mkbranch ${1} ${2}
# create PR
if ${NEED_PR}; then
  PR=$(mkpr ${2})
  echo "PR #${PR} created"
  checkpr
  [[ -z ${PR} ]] && { echo -e "\e[31mERR: Created PR but did not recieve PR number\e[0m"; exit 1; }
  mergepr

  # wait for argo to increment the version on the deploy which signals the start of the rollout
  deploywait ${1} ${2}

  # Delete the branch now that we are done with it
  cleanup ${1} ${2}
  exit 0
else
  echo "No changes to commit, working branch is clean."
  exit 0
fi