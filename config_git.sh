#!/usr/bin/env bash
set -euo pipefail

# Detect the remote's default branch (main, master, etc.)
DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"

if [[ -z "$DEFAULT_BRANCH" ]]; then
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

# Stash any uncommitted changes so rebase can proceed cleanly
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "git_config.sh temporary stash"
  STASHED=true
fi

# Restore stash on exit (whether success or failure)
restore_stash() {
  if [[ "$STASHED" == true ]]; then
    echo "Restoring stashed changes..."
    git stash pop
  fi
}
trap restore_stash EXIT

git rebase "$REMOTE_REF" --exec \
  "git commit --amend --reset-author --no-edit"

echo "Done."
