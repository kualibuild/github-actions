#!/bin/sh
set -eu

if [ -z "${INPUT_TOKEN}" ]; then
  echo "Missing github token; cannot replicate."
  exit 1
fi

if [ -z "${INPUT_TARGET_REPO}" ]; then
  echo "Missing repo; cannot replicate."
  exit 1
fi

git checkout -B replication
git filter-branch --index-filter "git rm --cached -f -r --ignore-unmatch .github" --tag-name-filter cat -- --all
export REMOTE="https://${INPUT_TOKEN}@github.com/${INPUT_TARGET_REPO}.git"
git push "${REMOTE}" replication:master --force
