#!/usr/bin/env bash
# Creates the private GitHub repository for this project and pushes the local history to it.
# Safe to run more than once: each action is skipped if it is already done.

# Stop at the first error, treat unset variables as errors, and fail if any command in a pipe fails
set -euo pipefail

# GitHub account that will own the repository; can be overridden by exporting GH_OWNER
GH_OWNER="${GH_OWNER:-kodatishrini-beep}"
# Repository name, the same as the project folder
REPO_NAME="${REPO_NAME:-OllamaControlCenter}"
# Short description shown on the GitHub repository page
REPO_DESC="${REPO_DESC:-Ollama monitor web app}"
# Project folder; can be overridden by exporting PROJECT_DIR before running
PROJECT_DIR="${PROJECT_DIR:-$HOME/OllamaControlCenter}"

# Work inside the project folder so the git commands act on this repository
cd "$PROJECT_DIR"

# Stop with a clear message if gh is not logged in (output hidden, only the exit code matters)
gh auth status > /dev/null 2>&1 || { echo "gh is not logged in: run 'gh auth login' first" >&2; exit 1; }

# Check whether the repository already exists on GitHub (output hidden, only the exit code matters)
if gh repo view "$GH_OWNER/$REPO_NAME" > /dev/null 2>&1; then
  # Nothing to create, tell the user
  echo "SKIP: GitHub repository $GH_OWNER/$REPO_NAME already exists"
else
  # Create an empty PRIVATE repository with the description (no files are uploaded yet)
  gh repo create "$GH_OWNER/$REPO_NAME" --private --description "$REPO_DESC"
# End of the repository existence check
fi

# Check whether this local repository already has a remote called origin
if git remote get-url origin > /dev/null 2>&1; then
  # Nothing to add, tell the user
  echo "SKIP: remote origin already set"
else
  # Store the GitHub address under the nickname origin (HTTPS, uses the gh login for credentials)
  git remote add origin "https://github.com/$GH_OWNER/$REPO_NAME.git"
# End of the remote check
fi

# Copy the local main branch to GitHub; -u links local main to origin/main for later plain 'git push'
git push -u origin main

# Show the remote addresses git knows about (read-only)
git remote -v
# Show name, visibility and description as stored on GitHub, to confirm it is private (read-only)
gh repo view "$GH_OWNER/$REPO_NAME" --json nameWithOwner,visibility,description
# Show the branch and whether it is in sync with GitHub (read-only)
git status -sb
