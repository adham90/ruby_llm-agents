#!/bin/bash
#
# Sync wiki/ folder to GitHub Wiki repository
#
# Usage: ./scripts/sync-wiki.sh [commit message]
#

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI_SOURCE="$REPO_ROOT/wiki"
WIKI_REPO_URL="git@github.com:adham90/ruby_llm-agents.wiki.git"
TEMP_DIR=$(mktemp -d)
COMMIT_MSG="${1:-Sync wiki from main repo}"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Syncing wiki to GitHub..."

# Clone wiki repo
echo "Cloning wiki repository..."
git clone --depth 1 "$WIKI_REPO_URL" "$TEMP_DIR" 2>/dev/null || {
    echo "Error: Could not clone wiki repo."
    echo "Make sure the wiki is initialized (create at least one page via GitHub UI first)."
    exit 1
}

# Remove old content (except .git)
echo "Updating content..."
find "$TEMP_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

# Copy new content
cp -r "$WIKI_SOURCE"/* "$TEMP_DIR/"

# Commit and push
cd "$TEMP_DIR"
git add -A

if git diff --staged --quiet; then
    echo "No changes to sync."
    exit 0
fi

git commit -m "$COMMIT_MSG"
git push origin master

echo "Wiki synced successfully!"
