#!/usr/bin/env bash
# Scenario tests for run.sh against throwaway git repos: a local bare repo plays
# `origin` and each case checks out a commit the way actions/checkout does, then
# runs the guard with the GitHub env vars set by hand. Needs only bash and git.
#
# Usage: superseded-guard/test.sh [path/to/bash]
set -uo pipefail
RUN="$(cd "$(dirname "$0")" && pwd)/run.sh"
BASH_BIN="${1:-bash}"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0 fail=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q --bare "$W/origin.git"
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$W/origin.git" "$W/dev" 2> /dev/null
git -C "$W/dev" switch -q -c main

# commit <file>: append to <file>, commit, push the current branch; prints the SHA.
commit() {
  mkdir -p "$W/dev/$(dirname "$1")"
  echo "$RANDOM" >> "$W/dev/$1"
  git -C "$W/dev" add -A
  git -C "$W/dev" commit -qm "$1"
  git -C "$W/dev" push -q origin "HEAD:$(git -C "$W/dev" branch --show-current)"
  git -C "$W/dev" rev-parse HEAD
}

# checkout <sha>: like actions/checkout's default, a depth-1 fetch of one commit.
# With FULL=1, a full clone (fetch-depth: 0) detached at <sha> instead.
checkout() {
  rm -rf "$W/ci"
  if [[ "${FULL:-0}" == 1 ]]; then
    git clone -q "$W/origin.git" "$W/ci" 2> /dev/null
    git -C "$W/ci" checkout -q --detach "$1"
  else
    git init -q "$W/ci"
    git -C "$W/ci" remote add origin "$W/origin.git"
    git -C "$W/ci" fetch -q --depth=1 origin "$1"
    git -C "$W/ci" checkout -q FETCH_HEAD
  fi
}

ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; sed 's/^/     /' "$W/log"; }

# run <name> <expect deploy> <expect exit> <checkout sha> [VAR=value...]
run() {
  local name=$1 want=$2 wantrc=$3 sha=$4 rc got
  shift 4
  checkout "$sha"
  : > "$W/out"
  : > "$W/sum"
  (cd "$W/ci" && env GITHUB_OUTPUT="$W/out" GITHUB_STEP_SUMMARY="$W/sum" GITHUB_SHA="$sha" \
    GITHUB_REF_NAME=main GITHUB_REF_TYPE=branch GITHUB_EVENT_NAME=push GITHUB_RUN_ATTEMPT=1 \
    PATHS="**" PATHS_IGNORE="" FAIL_ON_RERUN=true BRANCH="" SHA="" DEFAULT_BRANCH="" \
    "$@" "$BASH_BIN" "$RUN" > "$W/log" 2>&1)
  rc=$?
  got=$(sed -n 's/^deploy=//p' "$W/out")
  if [[ "$got" == "$want" && "$rc" == "$wantrc" ]]; then ok "$name"
  else bad "$name (deploy=$got rc=$rc, want deploy=$want rc=$wantrc)"; fi
}

# expect <file> <grep -E pattern> <name>: check the last run's log or summary.
expect() { if grep -qE -- "$2" "$W/$1"; then ok "$3"; else bad "$3 (no /$2/ in $1)"; fi; }

echo "# Superseded or current"
c1=$(commit app/a.txt)
run "tip of branch deploys"                          true  0 "$c1"
c2=$(commit app/b.txt)
run "superseded by deployable change: warn, skip"    false 0 "$c1"
expect log "^::warning::Not deploying" "  warning annotation"
expect sum "Deploy skipped" "  step summary written"
expect sum "^app/b.txt$" "  summary lists changed file"
run "superseded re-run fails"                        false 1 "$c1" GITHUB_RUN_ATTEMPT=2
expect log "^::error::Not deploying" "  error annotation"
run "superseded re-run, fail-on-rerun=false warns"   false 0 "$c1" GITHUB_RUN_ATTEMPT=2 FAIL_ON_RERUN=false
run "re-run of the tip deploys"                      true  0 "$c2" GITHUB_RUN_ATTEMPT=3

echo "# paths and paths-ignore"
c3=$(commit .github/workflows/deploy-secrets.yaml)
run "newer commit only touches paths-ignore"         true  0 "$c2" PATHS_IGNORE=".github/workflows/deploy-secrets.yaml"
run "same without paths-ignore is superseded"        false 0 "$c2"
c4=$(commit docs/readme.md)
run "change outside paths"                           true  0 "$c3" "PATHS=grafana/**"
c5=$(commit grafana/resources/dash.json)
run "change inside paths"                            false 0 "$c4" "PATHS=grafana/**"
run "! after a match excludes"                       true  0 "$c4" "PATHS=grafana/**
!grafana/resources/**"
run "positive after ! re-includes (order matters)"   false 0 "$c4" "PATHS=grafana/**
!grafana/resources/**
grafana/resources/dash.json"
run "multi-line paths, blank lines and comments"     false 0 "$c4" "PATHS=
  # deployable
  docs/**
  grafana/**
"
run "* stays within a directory"                     true  0 "$c4" "PATHS=*.json"
run "**/*.json matches nested files"                 false 0 "$c4" "PATHS=**/*.json"
run "**.json matches nested files (GitHub's **.js)"  false 0 "$c4" "PATHS=**.json"
run "grafana/**.json matches nested files"           false 0 "$c4" "PATHS=grafana/**.json"
c5r=$(commit README.md)
run "**/README.md matches a root README"             false 0 "$c5" "PATHS=**/README.md"
git -C "$W/dev" mv -q grafana/resources/dash.json archive/dash.json 2> /dev/null \
  || { mkdir -p "$W/dev/archive"; git -C "$W/dev" mv grafana/resources/dash.json archive/dash.json; }
git -C "$W/dev" commit -qm "move dash out"
git -C "$W/dev" push -q origin HEAD:main
run "moving a file out of paths counts"              false 0 "$c5r" "PATHS=grafana/**"
git -C "$W/dev" mv archive/dash.json grafana/resources/dash.json
git -C "$W/dev" commit -qm "move dash back"
git -C "$W/dev" push -q origin HEAD:main
c6=$(git -C "$W/dev" rev-parse HEAD)

echo "# Pattern mistakes fail loudly on every run"
run "YAML list item is rejected"                     ""    1 "$c6" "PATHS=- grafana/**"
expect log "^::error::.*YAML list" "  says why"
run "double-quoted pattern is rejected"              ""    1 "$c6" 'PATHS="grafana/**"'
run "single-quoted pattern is rejected"              ""    1 "$c6" "PATHS='grafana/**'"
run "quoted list item is rejected"                   ""    1 "$c6" 'PATHS=- "grafana/**"'
run "quoted ! pattern is rejected"                   ""    1 "$c6" 'PATHS=**
!"docs/**"'
run "! in paths-ignore is rejected"                  ""    1 "$c6" "PATHS_IGNORE=!docs/**"
expect log "^::error::.*paths-ignore only excludes" "  says why"
run "only ! patterns in paths is rejected"           ""    1 "$c6" "PATHS=!docs/**"
run "bare ! is rejected"                             ""    1 "$c6" "PATHS=!"
run "patterns matching no files warn"                true  0 "$c6" "PATHS=nothing-here/**"
expect log "^::warning::.*match no files" "  warning annotation"

echo "# History and moves"
git -C "$W/dev" push -q -f origin "$c4":main
run "branch force-pushed behind the run's commit"    false 0 "$c6" "PATHS=grafana/**"
git -C "$W/dev" push -q -f origin "$c6":main
cp "$W/dev/grafana/resources/dash.json" "$W/keep"
commit grafana/resources/dash.json > /dev/null
cp "$W/keep" "$W/dev/grafana/resources/dash.json"
git -C "$W/dev" commit -qam revert
git -C "$W/dev" push -q origin HEAD:main
run "later commits net to no change"                 true  0 "$c6" "PATHS=grafana/**"

echo "# Clone depth is left alone"
tip=$(git -C "$W/dev" rev-parse HEAD)
FULL=1 run "full clone at the tip deploys"           true  0 "$tip"
count=$(git -C "$W/ci" rev-list --count HEAD)
[[ "$(git -C "$W/ci" rev-parse --is-shallow-repository)" == false ]] \
  && ok "  full clone stays full ($count commits)" || bad "  full clone became shallow"
FULL=1 run "full clone, superseded"                  false 0 "$c1"
[[ "$(git -C "$W/ci" rev-parse --is-shallow-repository)" == false ]] \
  && ok "  full clone stays full" || bad "  full clone became shallow"
run "shallow clone, superseded"                      false 0 "$c1"

echo "# What is being deployed"
run "ref: checkout of an old commit is compared, not GITHUB_SHA" false 0 "$c1" GITHUB_SHA="$tip"
run "sha input fetches a commit missing from the checkout" false 0 "$tip" SHA="$c1"
run "sha input that doesn't exist errors"            ""    1 "$tip" SHA=0123456789abcdef0123456789abcdef01234567
expect log "^::error::.*could not fetch the commit to deploy" "  says why"

echo "# Events the guard doesn't apply to"
run "pull_request event is not guarded"              true  0 "$c1" GITHUB_EVENT_NAME=pull_request GITHUB_REF_NAME=7/merge
run "tag ref is not guarded"                         true  0 "$c1" GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.0.0

echo "# Deploy branch"
run "payload default_branch is used"                 true  0 "$tip" DEFAULT_BRANCH=main
run "unreadable branch errors clearly"               ""    1 "$c1" DEFAULT_BRANCH=no-such-branch
expect log "^::error::.*could not read 'no-such-branch'" "  says why"
git -C "$W/dev" switch -q -c feature
f1=$(commit grafana/resources/feature.json)
run "run from another branch is held to the primary" false 0 "$f1" GITHUB_REF_NAME=feature GITHUB_EVENT_NAME=workflow_dispatch
expect log "this run is from 'feature' and is compared against 'main'" "  names both branches"
run "  and its re-run fails"                         false 1 "$f1" GITHUB_REF_NAME=feature GITHUB_RUN_ATTEMPT=2
f2=$(commit docs/feature.md)
run "other branch matching primary in paths deploys" true  0 "$f2" GITHUB_REF_NAME=feature "PATHS=docs/**
!docs/feature.md"
run "branch input: tip of deploy branch deploys"     true  0 "$f2" BRANCH=feature GITHUB_REF_NAME=feature
f3=$(commit grafana/resources/feature.json)
run "branch input: superseded on deploy branch"      false 0 "$f2" BRANCH=feature GITHUB_REF_NAME=feature
expect log "Deploy from the newest feature run instead" "  points at the newest run"
run "branch input: superseded re-run fails"          false 1 "$f2" BRANCH=feature GITHUB_REF_NAME=feature GITHUB_RUN_ATTEMPT=2
run "branch input overrides payload default"         true  0 "$f3" BRANCH=feature DEFAULT_BRANCH=main
run "branch input accepts refs/heads/ prefix"        true  0 "$f3" BRANCH=refs/heads/feature
run "branch input: unknown branch errors"            ""    1 "$f3" BRANCH=no-such-branch
run "empty branch input falls back to primary"       false 0 "$f3"
git -C "$W/dev" switch -q main
git -C "$W/dev" push -q origin "$c1":refs/heads/trunk
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/trunk
run "primary detected from remote HEAD (trunk)"      false 0 "$tip"
run "tip of detected primary deploys"                true  0 "$c1" GITHUB_REF_NAME=trunk
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/main

echo "# Setup errors"
: > "$W/out"
(cd "$W" && env GITHUB_OUTPUT="$W/out" GITHUB_SHA="$c1" GITHUB_REF_NAME=main GITHUB_REF_TYPE=branch \
  GITHUB_EVENT_NAME=push "$BASH_BIN" "$RUN" > "$W/log" 2>&1)
rc=$?
if [[ $rc == 1 ]] && grep -q "checked out first" "$W/log"; then ok "no checkout errors clearly"
else bad "no checkout errors clearly (rc=$rc)"; fi

echo
echo "$pass passed, $fail failed (bash $("$BASH_BIN" -c 'echo $BASH_VERSION'))"
[[ $fail == 0 ]]
