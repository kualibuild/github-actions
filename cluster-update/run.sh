#!/usr/bin/env bash

USAGE="usage: ./run.sh [cluster_name] [region]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

go run main.go -c ${1} -r ${2}