#!/bin/sh
set -eu

# ORG="$(printf ${GITHUB_REPOSITORY} | sed -r 's/^([^/]*).*$/\1/')"
PACKAGE_PATH="${INPUT_PACKAGE_PATH}"
NPM_REGISTRY="${INPUT_NPM_REGISTRY}"
export NPM_REGISTRY_AUTH="$(printf ${NPM_REGISTRY} | sed 's/^[^\/]*//' | sed 's/\/$//')"
export NPM_TOKEN="${INPUT_NPM_TOKEN}"

echo "${NPM_REGISTRY_AUTH}/:_authToken=\"${NPM_TOKEN}\"" >> ~/.npmrc

cd "${PACKAGE_PATH}"

if [ ! -f "package.json" ]; then
  echo "No package.json found in $(pwd)"
  exit 1
fi

pwd
ls -la

PACKAGE_NAME="$(cat package.json | jq -r .name)"
CURRENT_VERSION="$(cat package.json | jq -r .version)"
REMOTE_VERSION="$(npm view "${PACKAGE_NAME}" --registry "${NPM_REGISTRY}" version || true)"

if [ "${CURRENT_VERSION}" != "${REMOTE_VERSION}" ]; then
  npm publish --registry "${NPM_REGISTRY}"
else
  echo 'Skipped because package.json version has not been updated'
fi
