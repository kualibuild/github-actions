#!/usr/bin/env bash

die() {
	local _ret="${2:-1}"
	echo "$1" >&2
	exit "${_ret}"
}

if ! hash kubeval 2>/dev/null; then
    die "ERROR: kubeval was not found in \$PATH"
fi

export TERM="xterm-256color"
cd $1
err=0
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)
for f in $(find . -iname '*.yaml' -type f | grep -Ev 'values.yaml|applications.yaml|application.yaml|kustomization.yaml|bootstrapper.yaml|/patches/|/configs/'); do
  readarray -t <<<$(kubeval --ignore-missing-schemas --quiet ${f})
  for x in "${MAPFILE[@]}"; do
    rr=$(echo ${x} | cut -d' ' -f3-)
    echo -n "  * "
    case "${x%% *}" in
      ERR) ((err+=1)); echo "${red}${x%% *}${reset} - ${rr}";;
      WARN) echo "${yellow}${x%% *}${reset} - ${rr}";;
      PASS) echo "${green}${x%% *}${reset} - ${rr}";;
    esac
  done
done
[ ${err} -gt 0 ] && exit 1
exit 0