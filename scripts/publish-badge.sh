#!/usr/bin/env bash
#
# Publish a single shields.io "endpoint" JSON badge to its own orphan branch so
# README badges work without any external account. Each badge gets a dedicated
# branch to avoid concurrent CI jobs clobbering each other.
#
# Usage: publish-badge.sh <branch> <filename> <json-content>
#
# Requires GITHUB_TOKEN and GITHUB_REPOSITORY in the environment.

set -euo pipefail

BRANCH="${1:?usage: publish-badge.sh <branch> <filename> <json-content>}"
FILENAME="${2:?filename required}"
JSON="${3:?json content required}"

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

TMP="$(mktemp -d)"
cd "$TMP"

git init -q
git checkout -q -b "$BRANCH"
printf '%s' "$JSON" > "$FILENAME"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$FILENAME"
git commit -qm "Update $FILENAME [skip ci]"
git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$BRANCH"

echo "Published $FILENAME to branch '$BRANCH'"
