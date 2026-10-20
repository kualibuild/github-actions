#!/usr/bin/env bash
# Decide whether this run's commit is still the newest deployable state of the
# deploy branch (the `branch` input, else the repository's primary branch).
# Writes deploy=true|false (and the compared tip) to $GITHUB_OUTPUT.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

# Only branch runs can be superseded. A pull request's merge ref or a tag is
# deployed as-is, so the guard steps aside rather than guessing.
if [[ "${GITHUB_REF_TYPE:-}" != "branch" || "${GITHUB_EVENT_NAME:-}" == pull_request* ]]; then
  echo "Guard not applied: a ${GITHUB_EVENT_NAME:-?} run on ${GITHUB_REF_TYPE:-?} '${GITHUB_REF_NAME:-?}' cannot be superseded."
  out deploy true
  out tip ""
  exit 0
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "::error::superseded-guard needs the repository checked out first (actions/checkout)."
  exit 1
fi

# Compare against the deploy branch: the `branch` input when a workflow deploys
# from somewhere else, otherwise the primary branch, as pdf-api's original guard
# did with a hard-coded `master`. A run from any other branch is held to what
# the deploy branch would deploy. The event payload names the primary branch for
# most events; otherwise ask the remote, which works for any checkout.
branch="${BRANCH:-${DEFAULT_BRANCH:-}}"
branch="${branch#refs/heads/}"
if [[ -z "$branch" ]]; then
  branch=$(git ls-remote --symref origin HEAD | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p' || true)
fi
if [[ -z "$branch" ]]; then
  echo "::error::Could not determine the repository's primary branch."
  exit 1
fi

if ! git fetch --no-tags --depth=1 origin "refs/heads/$branch"; then
  echo "::error::Could not fetch '$branch' from origin to compare against."
  exit 1
fi
tip=$(git rev-parse FETCH_HEAD)
out tip "$tip"

if [[ "$tip" == "$GITHUB_SHA" ]]; then
  echo "Deploying ${GITHUB_SHA::8}: it is the tip of $branch."
  out deploy true
  exit 0
fi

# A checkout of some other ref may not contain the run's own commit.
git cat-file -e "${GITHUB_SHA}^{commit}" 2> /dev/null \
  || git fetch --no-tags --depth=1 origin "$GITHUB_SHA"

# Translate GitHub `paths` / `paths-ignore` globs into git pathspecs. A leading
# `!` excludes, as in `on.push.paths`. Excludes apply regardless of order.
specs=()
includes=0
add_specs() { # $1: newline-separated patterns; $2: "exclude" to exclude every pattern
  local p
  while IFS= read -r p; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -z "$p" || "$p" == \#* ]] && continue
    if [[ "$p" == !* ]]; then
      specs+=(":(glob,exclude)${p#!}")
    elif [[ "$2" == exclude ]]; then
      specs+=(":(glob,exclude)$p")
    else
      specs+=(":(glob)$p")
      includes=1
    fi
  done <<< "$1"
}
add_specs "${PATHS:-}" include
add_specs "${PATHS_IGNORE:-}" exclude
(( includes )) || specs=(":(glob)**" "${specs[@]+"${specs[@]}"}")

changed=$(git diff --name-only "$GITHUB_SHA" "$tip" -- "${specs[@]}")

if [[ -z "$changed" ]]; then
  echo "Deploying ${GITHUB_SHA::8}: $branch has moved to ${tip::8}, but no deployable files changed."
  out deploy true
  exit 0
fi

out deploy false
msg="Not deploying ${GITHUB_SHA::8}: $branch is at ${tip::8}, which changes deployable files. Deploy from the newest $branch run instead."
{
  echo "### Deploy skipped: superseded commit"
  echo
  echo "$msg"
  echo
  echo "Deployable files that differ from the tip:"
  echo '```'
  head -n 20 <<< "$changed"
  if (( $(wc -l <<< "$changed") > 20 )); then echo "..."; fi
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

if [[ "${GITHUB_RUN_ATTEMPT:-1}" -gt 1 && "${FAIL_ON_RERUN:-true}" == "true" ]]; then
  echo "::error::$msg (Re-running an old run redeploys old code.)"
  exit 1
fi
echo "::warning::$msg"
