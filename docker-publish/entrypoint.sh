#!/bin/sh
set -eu

REPO_NAME="$(printf ${GITHUB_REPOSITORY} | sed -r 's/^([^/]*)\/(.*)$/\2/')"
DOCKER_REGISTRY="${INPUT_DOCKER_REGISTRY}"
DOCKER_IMAGE_NAME="${INPUT_DOCKER_IMAGE_NAME:-${REPO_NAME}}"
DOCKER_USERNAME="${INPUT_DOCKER_USERNAME}"
DOCKER_PASSWORD="${INPUT_DOCKER_PASSWORD}"
DOCKER_CONTEXT_PATH="${INPUT_DOCKER_CONTEXT_PATH}"
DOCKER_DOCKERFILE="${INPUT_DOCKERFILE}"
BUILD_PARAMS="${INPUT_BUILD_PARAMS}"
BRANCH="$(echo ${GITHUB_REF} | sed -e "s/refs\/heads\///g")"
PULL_STAGES_LOG=pull-stages-output.log

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

BUILD_PARAMS="$BUILD_PARAMS --file ${DOCKER_DOCKERFILE}"

if [ "$INPUT_PULL_IMAGE_AND_STAGES" == true ]; then
  docker pull --all-tags "${BASE_DOCKERNAME}"-stages 2> /dev/null | tee "$PULL_STAGES_LOG" || true
fi

MAX_STAGE="$(sed -nr 's/^([0-9]+): Pulling from.+/\1/p' "$PULL_STAGES_LOG" | sort -n | tail -n 1)"

CACHE_FROM=''
if [ "$MAX_STAGE" ]; then
  CACHE_FROM=$(eval "echo --cache-from=$(BASE_DOCKERNAME)-stages:{1..$MAX_STAGE}")
fi

docker build ${CACHE_FROM} --tag ${SHA_DOCKERNAME} --tag ${DOCKERNAME} ${BUILD_PARAMS} $DOCKER_CONTEXT_PATH
docker push ${SHA_DOCKERNAME}
docker push ${DOCKERNAME}

docker logout
