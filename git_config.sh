#!/usr/bin/env bash
set -euo pipefail

# Detect the remote's default branch (main, master, etc.)
DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"

if [[ -z "$DEFAULT_BRANCH" ]]; then
  # refs/remotes/origin/HEAD not set — fetch it from the remote
  git remote set-head origin --auto
  DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/origin/||')"
fi

REMOTE_REF="origin/$DEFAULT_BRANCH"
echo "Using remote ref: $REMOTE_REF"

# Pull name and email from the last commit on the remote default branch
USER_NAME="$(git log "$REMOTE_REF" -1 --format='%an')"
USER_EMAIL="$(git log "$REMOTE_REF" -1 --format='%ae')"

# Set config for future commits
git config user.name  "$USER_NAME"
git config user.email "$USER_EMAIL"
echo "Config set to: $USER_NAME <$USER_EMAIL>"

# Rewrite any local commits not yet pushed
UNPUSHED=$(git rev-list "$REMOTE_REF"..HEAD)

if [[ -z "$UNPUSHED" ]]; then
  echo "No unpushed commits to rewrite."
  exit 0
fi

echo "Rewriting unpushed commits to: $USER_NAME <$USER_EMAIL>"

git filter-branch -f --env-filter "
  GIT_AUTHOR_NAME='$USER_NAME'
  GIT_AUTHOR_EMAIL='$USER_EMAIL'
  GIT_COMMITTER_NAME='$USER_NAME'
  GIT_COMMITTER_EMAIL='$USER_EMAIL'
" "$REMOTE_REF"..HEAD

echo "Done."
