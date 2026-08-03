#!/usr/bin/env bash
# Copyright © 2020-2026 Kuali, Inc. - All Rights Reserved
#
# Requests review from the DevOps reviewers when a PR changes the [[vm]] block
# of any watched fly.toml. Capacity changes (cpus, memory, size) need a second
# pair of eyes; everything else in these files does not.

set -euo pipefail

: "${FILES:?files input is required}"
: "${REPO:?}" "${PR_NUMBER:?}" "${BASE_SHA:?}" "${HEAD_SHA:?}"

if [ -z "${TEAMS:-}" ] && [ -z "${REVIEWERS:-}" ]; then
  echo "::error::Neither teams nor reviewers was set - nobody would be requested"
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Print the [[vm]] table and any [vm.*] subtables, stopping at the next
# top-level table. Matching on the section rather than on key names keeps this
# correct for both schemas in use (cpu_kind/cpus/memory, and size) and for
# files where [[vm]] is not the last block.
extract_vm() {
  awk '
    /^[[:space:]]*\[\[vm\]\]/                  { inv = 1; print; next }
    inv && /^[[:space:]]*\[/ && !/^[[:space:]]*\[vm\./ { inv = 0 }
    inv                                        { print }
  '
}

# A file absent from a revision yields an empty block, so added and deleted
# fly configs compare cleanly instead of erroring.
vm_at() {
  git show "$1:$2" 2>/dev/null | extract_vm || true
}

changed=0
for file in $FILES; do
  vm_at "$BASE_SHA" "$file" >"$work/base"
  vm_at "$HEAD_SHA" "$file" >"$work/head"

  if ! diff -q "$work/base" "$work/head" >/dev/null 2>&1; then
    echo "::notice file=$file::[[vm]] block changed"
    diff -u --label "a/$file" --label "b/$file" "$work/base" "$work/head" || true
    changed=1
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "No [[vm]] changes in: $FILES"
  exit 0
fi

pending_teams=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq '.requested_teams[].slug' 2>/dev/null || true)
pending=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq '.requested_reviewers[].login' 2>/dev/null || true)

# A team is requested as a unit, so members who have not accepted their org
# invitation yet are simply absent rather than causing a failure, and they are
# picked up automatically once they join - no change here needed.
for team in ${TEAMS:-}; do
  if grep -qxF "$team" <<<"$pending_teams"; then
    echo "Skipping team $team (review already requested)"
    continue
  fi

  requested=$(gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
    -f "team_reviewers[]=$team" --jq '.requested_teams[].slug' 2>/dev/null || true)

  if grep -qxF "$team" <<<"$requested"; then
    echo "Requested review from team $team"
  else
    echo "::warning::Could not request review from team $team - check the slug is correct and the team has access to $REPO"
  fi
done

# One request per reviewer, so one bad login cannot take the others down with
# it. Success is read back from the response rather than the exit code: GitHub
# answers 200 and silently adds nobody when a login does not exist (a real
# account merely lacking access gives 422 instead), so an unnoticed typo or
# renamed account would otherwise look like it worked.
for user in ${REVIEWERS:-}; do
  if [ "$user" = "${PR_AUTHOR:-}" ]; then
    echo "Skipping $user (PR author)"
    continue
  fi

  if grep -qxF "$user" <<<"$pending"; then
    echo "Skipping $user (review already requested)"
    continue
  fi

  requested=$(gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
    -f "reviewers[]=$user" --jq '.requested_reviewers[].login' 2>/dev/null || true)

  if grep -qxF "$user" <<<"$requested"; then
    echo "Requested review from $user"
  else
    echo "::warning::Could not request review from $user - check the login is spelled correctly and has access to $REPO"
  fi
done
