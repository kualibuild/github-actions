#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved

die() {
	local _ret="${2:-1}"
	echo "$1" >&2
	exit "${_ret}"
}

if ! hash kustomize 2>/dev/null; then
    die "ERROR: kustomize was not found in \$PATH"
fi

kval() {
  echo "Validating kustomize manifests in ${1}"
  [[ ${1} =~ "tests" ]] && break
  result=$(kustomize build ${1} -o /dev/null 2>&1)
  if [ $(echo ${result} | wc -w) -eq 0 ]; then
    echo "  * ${green}PASS${reset} - ${1} is buildable by kustomize"
  else
    ((err+=1))
    echo "  * ${red}FAIL${reset} - ${1} ${result}"
  fi
}

cd ${1}
export TERM="xterm-256color"
err=0
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
if echo * | grep kustomization.yaml &>/dev/null; then
  cd ..
  kval ${1}
else
  for d in $(echo */); do 
    kval ${d}
  done
fi
[ ${err} -gt 0 ] && exit 1
exit 0