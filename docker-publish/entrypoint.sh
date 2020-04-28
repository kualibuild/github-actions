#!/bin/sh
set -eu

if [ -z "${INPUT_DOCKER_PASSWORD}" ]; then
  echo "Unable to find the password. Did you set with.docker_password?"
  exit 1
fi

REPO_NAME="$(printf ${GITHUB_REPOSITORY} | sed -r 's/^([^/]*)\/(.*)$/\2/')"
DOCKER_REGISTRY="${INPUT_DOCKER_REGISTRY}"
DOCKER_IMAGE_NAME="${INPUT_DOCKER_IMAGE_NAME:-${REPO_NAME}}"
DOCKER_USERNAME="${INPUT_DOCKER_USERNAME:-${GITHUB_ACTOR}}"
DOCKER_PASSWORD="${INPUT_DOCKER_PASSWORD}"
DOCKER_CONTEXT_PATH="${INPUT_DOCKER_CONTEXT_PATH}"
DOCKER_DOCKERFILE="${INPUT_DOCKERFILE}"
BUILD_PARAMS="${INPUT_BUILD_PARAMS}"
BRANCH="$(echo ${GITHUB_REF} | sed -e "s/refs\/heads\///g")"

if [ "${BRANCH}" == "master" ]; then
  BRANCH="latest"
fi;

# if contains /refs/tags/
if [ $(echo ${GITHUB_REF} | sed -e "s/refs\/tags\///g") != ${GITHUB_REF} ]; then
  BRANCH="latest"
fi;

printf ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin ${DOCKER_REGISTRY}

BASE_DOCKERNAME="${DOCKER_REGISTRY}/${GITHUB_REPOSITORY}/${DOCKER_IMAGE_NAME}"
DOCKERNAME="${BASE_DOCKERNAME}:${BRANCH}"
timestamp=`date +%Y%m%d%H%M%S`
short_sha=$(echo "${GITHUB_SHA}" | cut -c1-6)
SHA_DOCKERNAME="${BASE_DOCKERNAME}:${timestamp}${short_sha}"

BUILD_PARAMS="$BUILD_PARAMS -f ${DOCKER_DOCKERFILE}"

docker build ${BUILD_PARAMS} -t ${SHA_DOCKERNAME} -t ${DOCKERNAME} $DOCKER_CONTEXT_PATH
docker push ${SHA_DOCKERNAME}
docker push ${DOCKERNAME}

docker logout
