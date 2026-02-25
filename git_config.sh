#!/usr/bin/env bash
set -euo pipefail

# Pull name and email from the last commit on origin/main
USER_NAME="$(git log origin/main -1 --format='%an')"
USER_EMAIL="$(git log origin/main -1 --format='%ae')"

# Set config for future commits
git config user.name  "$USER_NAME"
git config user.email "$USER_EMAIL"

# Rewrite any local commits not yet pushed to origin/main
UNPUSHED=$(git rev-list origin/main..HEAD)

if [[ -z "$UNPUSHED" ]]; then
  echo "No unpushed commits to rewrite."
  exit 0
fi

echo "Rewriting unpushed commits to author: $USER_NAME <$USER_EMAIL>"

git filter-branch -f --env-filter "
  GIT_AUTHOR_NAME='$USER_NAME'
  GIT_AUTHOR_EMAIL='$USER_EMAIL'
  GIT_COMMITTER_NAME='$USER_NAME'
  GIT_COMMITTER_EMAIL='$USER_EMAIL'
" origin/main..HEAD

echo "Done."
