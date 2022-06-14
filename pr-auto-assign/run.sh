#!/usr/bin/env bash

USAGE="usage: ./run.sh [reviewers]"
if [[ $# -lt 1 ]]; then
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

./${PWD##*/}-${o}-${a} ${1} --debug