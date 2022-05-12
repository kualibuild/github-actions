#!/usr/bin/env bash

USAGE="usage: ./run.sh [path] [version] [skiptests] [softfail]"
if [[ $# -lt 4 ]]; then
  echo "${USAGE}"
  exit 1
fi

# validate inputs
ver=${2}
skip=${3}
soft=${4}
bool=("true" "false")
# [[ -z ${GITHUB_REPO} ]] && { echo "ERR: GITHUB_REPO not set"; exit 1; }
# [[ -z ${GITHUB_TOKEN} ]] && { echo "ERR: GITHUB_TOKEN not set"; exit 1; }
# [[ -z ${GITHUB_USER} ]] && { echo "ERR: GITHUB_USER not set"; exit 1; }
[[ ! -d ${1} ]] && { echo "ERR: path ${1} does not exist"; exit 1; } || { path=${1}; }
[[ -f ${path}/kustomization.yaml ]] && fname="kustomization.yaml"
[[ -f ${path}/kustomization.yml ]] && fname="kustomization.yml"
[[ -f ${path}/Kustomization ]] && fname="Kustomization"
[[ -z ${fname} ]] && { echo "ERR: unable to find one of 'kustomization.yaml', 'kustomization.yml' or 'Kustomization' in directory `${1}`"; exit 1; }
[[ ! ${bool[@]} =~ ${skip} ]] && { echo "ERR: skiptests must be 'true' or 'false'"; exit 1; }
[[ ! ${bool[@]} =~ ${soft} ]] && { echo "ERR: softfail must be 'true' or 'false'"; exit 1; }

# update tag
gsed -i "s/^    newTag: .*$/    newTag: \'${ver}\'/" ${path}/${fname}

raw=$(kustomize build ${path})
resources=$(echo "${raw}" | kubectl apply --dry-run=client -f - | cut -d' ' -f1)
ns=$(echo "${raw}" | grep -A 20 'kind: Deployment' |  grep 'namespace' | awk '{print $2}')
name=$(echo "${resources}" | grep deployment | cut -d'/' -f2)
kubectl get ns ${ns} &>/dev/null || { echo "ERR: namespace ${ns} does not exist"; exit 1; }

cleanup() {
  kubectl -n ${ns} scale deployment/${name} --replicas=0
  kubectl -n ${ns} rollout status deployment/${name}
  kubectl -n ${ns} delete ${resources}
  exit ${1}
}

# deploy smoke resources
echo "${raw}" | kubectl apply -f -

# scale up to 1
kubectl -n ${ns} scale deployment/${name} --replicas=1 || { echo "ERR: unable to scale deployment ${name} to 1"; cleanup 1; }
timeout 60 kubectl -n ${ns} rollout status deployment/${name} || { echo "ERR: deployment ${name} failed to deploy"; cleanup 1; }
kubectl wait -n ${ns} --for=condition=Ready pods --selector app=${name} --timeout=60s || { echo "ERR: deployment ${name} failed to deploy"; cleanup 1; }

# set up port-forward
pod=$(kubectl -n ${ns} get po -l app=${name} -o jsonpath='{.items[0].metadata.name}')
echo $pod
kubectl -n ${ns} port-forward pod/${pod} 8080:80 &>/dev/null &

# run tests
fail=0
if [[ ${skip} == "true" ]]; then
  echo "skipping tests"
else
  cur=$(pwd)
  cd ${path}/tests
  for i in $(find . -maxdepth 1 -perm -111 -type f); do
    ./${i}
    [[ $? -ne 0 ]] && ((fail+=1))
  done
  cd ${cur}
fi
kill %1

# clean up
if [[ ${soft} == "true" ]]; then
  echo "softfail: ${fail} tests failed"
  cleanup 0
else
  [[ ${fail} -ne 0 ]] && cleanup 1 || cleanup 0
fi
