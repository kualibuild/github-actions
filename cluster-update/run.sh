#!/usr/bin/env bash
# Copyright © 2020-2025 Kuali, Inc. - All Rights Reserved

USAGE="usage: ./run.sh [cluster_name] [region]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Running on Mac OS"
  export o=darwin
else
  echo "Running on Linux OS"
  export o=linux
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  echo "Running on 64-bit architecture"
  export a=amd64
else
  echo "Running on 32-bit architecture"
  export a=arm64
fi

./${PWD##*/}-${o}-${a} -c ${1} -r ${2}