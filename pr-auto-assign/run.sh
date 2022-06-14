#!/usr/bin/env bash

USAGE="usage: ./run.sh [reviewers]"
if [[ $# -lt 2 ]]; then
  echo "${USAGE}"
  exit 1
fi

go run main.go -c ${1}