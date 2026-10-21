#!/usr/bin/env bash
# Decide whether this run's commit is still the newest deployable state of the
# deploy branch (the `branch` input, else the repository's primary branch).
# Writes deploy=true|false (and the compared tip) to $GITHUB_OUTPUT.
set -euo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
fail() { echo "::error::superseded-guard: $1"; exit 1; }

# Only branch runs can be superseded. A pull request's merge ref or a tag is
# deployed as-is, so the guard steps aside rather than guessing.
if [[ "${GITHUB_REF_TYPE:-}" != "branch" || "${GITHUB_EVENT_NAME:-}" == pull_request* ]]; then
  echo "Guard not applied: a ${GITHUB_EVENT_NAME:-?} run on ${GITHUB_REF_TYPE:-?} '${GITHUB_REF_NAME:-?}' cannot be superseded."
  out deploy true
  out tip ""
  exit 0
fi

git rev-parse --git-dir > /dev/null 2>&1 \
  || fail "needs the repository checked out first (actions/checkout)."

# --- Deployable paths -------------------------------------------------------
# `paths` and `paths-ignore` use GitHub's filter syntax and are matched here the
# way GitHub matches them, so the guard and the trigger agree on every file.
# They are parsed before anything else so a malformed list fails every run, not
# only the superseded ones where it would otherwise go unnoticed.

# Convert one GitHub filter pattern to an anchored ERE: `*` stops at `/`, `**`
# crosses directories (`**/` may match nothing, so `**/x` matches a root `x`),
# and `?` / `+` quantify the preceding character, as in GitHub's cheat sheet.
glob_re() {
  local g=$1 re="" c j i=0 n=${#1}
  while (( i < n )); do
    c=${g:i:1}
    if [[ "$c" == "*" && "${g:i+1:1}" == "*" ]]; then
      if [[ "${g:i+2:1}" == "/" ]]; then re+="(.*/)?"; i=$((i + 3)); else re+=".*"; i=$((i + 2)); fi
      continue
    fi
    case "$c" in
      "*") re+="[^/]*" ;;
      "[")
        j=$((i + 1))
        while (( j < n )) && [[ "${g:j:1}" != "]" ]]; do j=$((j + 1)); done
        if (( j < n )); then re+=${g:i:j-i+1}; i=$((j + 1)); continue; fi
        re+="\\["
        ;;
      "." | "(" | ")" | "{" | "}" | "|" | "^" | "$" | "\\") re+="\\$c" ;;
      *) re+=$c ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$' "$re"
}

inc_re=() inc_neg=() ign_re=()
has_include=0
parse_patterns() { # $1: newline-separated patterns; $2: input name (paths | paths-ignore)
  local p body neg
  while IFS= read -r p; do
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    [[ -z "$p" || "$p" == \#* ]] && continue
    [[ "$p" =~ ^-[[:space:]] ]] \
      && fail "$2: '$p' is YAML list syntax; give one bare glob per line (no '- ')."
    body=$p neg=0
    if [[ "$body" == !* ]]; then
      [[ "$2" == paths-ignore ]] \
        && fail "paths-ignore: '$p': GitHub's paths-ignore only excludes and has no '!' patterns; use paths with '!' instead."
      body=${body#!} neg=1
    fi
    [[ "$body" == [\"\']* || "$body" == *[\"\'] ]] \
      && fail "$2: '$p' is quoted; give one bare glob per line (no quotes)."
    [[ -n "$body" ]] || fail "$2: '$p' has no pattern after '!'."
    if [[ "$2" == paths ]]; then
      inc_re+=("$(glob_re "$body")")
      inc_neg+=("$neg")
      (( neg )) || has_include=1
    else
      ign_re+=("$(glob_re "$body")")
    fi
  done <<< "$1"
}
parse_patterns "${PATHS:-}" paths
parse_patterns "${PATHS_IGNORE:-}" paths-ignore
if (( ${#inc_re[@]} == 0 )); then
  inc_re=("^.*$") inc_neg=(0)
elif (( ! has_include )); then
  fail "paths: '!' patterns need at least one pattern without '!', as in on.push.paths."
fi

# A file is deployable when the last `paths` pattern it matches is positive
# (GitHub's order rule) and no `paths-ignore` pattern matches it.
deployable() {
  local f=$1 i re hit=1
  for i in "${!inc_re[@]}"; do
    if [[ "$f" =~ ${inc_re[i]} ]]; then
      if (( inc_neg[i] )); then hit=1; else hit=0; fi
    fi
  done
  (( hit == 0 )) || return 1
  for re in ${ign_re[@]+"${ign_re[@]}"}; do
    if [[ "$f" =~ $re ]]; then return 1; fi
  done
  return 0
}
filter_deployable() {
  local f
  while IFS= read -r f; do
    if deployable "$f"; then echo "$f"; fi
  done
}

# --- Commits ----------------------------------------------------------------
# Fetch a commit only if it's missing, and never deepen or shallow the clone: a
# full (fetch-depth: 0) checkout must keep its history for later steps.
fetch_commit() { # $1: sha; $2: what it is, for the error message
  git cat-file -e "$1^{commit}" 2> /dev/null && return 0
  local depth=()
  [[ "$(git rev-parse --is-shallow-repository)" == true ]] && depth=(--depth=1)
  git fetch -q --no-tags ${depth[@]+"${depth[@]}"} origin "$1" \
    || fail "could not fetch $2 (${1::8}) from origin. The fetch needs actions/checkout's persisted credentials (don't set persist-credentials: false)."
}

# What is being deployed: the `sha` input, else whatever is checked out. That is
# GITHUB_SHA for an ordinary checkout, but not for a `ref:` checkout such as a
# workflow_run deploy of head_sha, where GITHUB_SHA is the branch tip.
sha=${SHA:-}
[[ -n "$sha" ]] || sha=$(git rev-parse HEAD)
fetch_commit "$sha" "the commit to deploy"
sha=$(git rev-parse "$sha^{commit}")

if [[ -z "$(git -c core.quotepath=false ls-tree -r --name-only "$sha" | filter_deployable | head -n 1)" ]]; then
  echo "::warning::superseded-guard: paths/paths-ignore match no files in ${sha::8}, so no change can count as deployable. Check the patterns."
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
[[ -n "$branch" ]] \
  || fail "could not determine the repository's primary branch. Reading it from origin needs actions/checkout's persisted credentials."

# Read the tip without fetching, so the common "still the tip" case touches
# nothing in the clone.
tip=$(git ls-remote origin "refs/heads/$branch" | awk -v ref="refs/heads/$branch" '$2 == ref { print $1 }' || true)
[[ -n "$tip" ]] \
  || fail "could not read '$branch' from origin to compare against. Check the branch exists; reading it needs actions/checkout's persisted credentials."
out tip "$tip"

if [[ "$tip" == "$sha" ]]; then
  echo "Deploying ${sha::8}: it is the tip of $branch."
  out deploy true
  exit 0
fi

fetch_commit "$tip" "the tip of $branch"
# --no-renames lists both sides of a rename, so moving a file out of a
# deployable path still counts as a deployable change.
changed=$(git -c core.quotepath=false diff --name-only --no-renames "$sha" "$tip" | filter_deployable)

if [[ -z "$changed" ]]; then
  echo "Deploying ${sha::8}: $branch has moved to ${tip::8}, but no deployable files changed."
  out deploy true
  exit 0
fi

out deploy false
if [[ "${GITHUB_REF_NAME:-}" == "$branch" ]]; then
  msg="Not deploying ${sha::8}: $branch is at ${tip::8}, which changes deployable files. Deploy from the newest $branch run instead."
else
  msg="Not deploying ${sha::8}: this run is from '${GITHUB_REF_NAME:-?}' and is compared against '$branch', which is at ${tip::8} with different deployable files."
fi
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
