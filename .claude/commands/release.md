---
description: Release a new version of ruby_llm-agents to RubyGems and GitHub
argument-hint: [patch|minor|major] (optional - auto-detected from changes if omitted)
allowed-tools: Bash, Read, Edit, Glob, Grep, Write, AskUserQuestion
---

# Ruby LLM Agents Release Command

You are automating a gem release for `ruby_llm-agents`. The user has provided: `$ARGUMENTS`

## Step 1: Prerequisites Check

Verify required tools are available:
```bash
which gem && which gh && which bundle
```

If any are missing, inform the user what needs to be installed and stop.

## Step 2: Pre-flight Checks

Run these checks and stop if any fail:

```bash
# Check we're on main branch
git branch --show-current

# Check git status is clean
git status --porcelain

# Pull latest changes
git pull --ff-only origin main
```

- If not on `main` branch, warn the user and ask if they want to continue.
- If there are uncommitted changes, stop and ask the user to commit or stash them.
- If pull fails, warn and ask if they want to continue.

## Step 3: Read Current Version

Read the current version from `lib/ruby_llm/agents/core/version.rb`. Parse the `VERSION = "X.Y.Z"` string to extract major, minor, and patch numbers.

## Step 4: Determine Version Bump Type

If the user provided an explicit bump type (`patch`, `minor`, or `major`) as `$ARGUMENTS`, use that.

Otherwise, **automatically detect** the bump type by analyzing changes since the last git tag:

### 4a: Gather Change Data

Run these commands to collect change information:

```bash
# Get the last tag
git describe --tags --abbrev=0

# Commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Files changed since last tag
git diff --name-only $(git describe --tags --abbrev=0)..HEAD

# Full diff stat
git diff --stat $(git describe --tags --abbrev=0)..HEAD
```

Also read `CHANGELOG.md` and look for any **unreleased section** at the top (a version entry that matches the next version or has no tag yet).

### 4b: Apply Semver Rules

Analyze ALL of the following signals to determine the bump type:

**MAJOR (X+1.0.0)** — if ANY of these are true:
- CHANGELOG has a `### Breaking Changes` section in the unreleased entry
- Commit messages contain `BREAKING CHANGE`, `BREAKING:`, or use conventional commit `!:` suffix (e.g., `feat!:`, `fix!:`)
- Commit messages mention "remove", "drop support", "rename" for public APIs

**MINOR (X.Y+1.0)** — if ANY of these are true (and no major signals):
- CHANGELOG has a `### Added` section in the unreleased entry
- Commit messages start with `Add `, `feat:`, `feat(`, or mention "new feature", "new module", "new class"
- New files were created under `lib/` (not just specs or docs)
- New configuration options were added
- New public API methods or modules were introduced

**PATCH (X.Y.Z+1)** — if NONE of the above (default):
- CHANGELOG only has `### Fixed` or `### Changed` sections
- Only bug fixes, documentation updates, test additions, or refactoring
- Commit messages start with `Fix `, `fix:`, `Update `, `Refactor `
- Changes are only in `spec/`, `wiki/`, `docs/`, or `README.md`

### 4c: Present Recommendation

Display the analysis to the user with clear reasoning:

> ## Version Analysis
>
> **Current version**: {current_version}
> **Last tag**: {last_tag}
> **Commits since last tag**: {count}
>
> **Signals detected**:
> - {list each signal found, e.g., "CHANGELOG has '### Added' section", "12 new files under lib/", etc.}
>
> **Recommended bump**: **{type}** → **{new_version}**
>
> | Option | Version | When to use |
> |--------|---------|-------------|
> | `patch` | {patch_version} | Bug fixes, docs, refactoring |
> | `minor` | {minor_version} | New features, backwards compatible |
> | `major` | {major_version} | Breaking changes |

Then use `AskUserQuestion` with the recommended option first (marked as "Recommended"), and the other two as alternatives, so the user can confirm or override.

## Step 5: Run Tests

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && bundle exec rake spec
```

If tests fail, stop immediately and report the failures. Do not proceed with the release.

## Step 6: Run Linter

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && bundle exec standardrb
```

If linting fails, attempt auto-fix:
```bash
bundle exec standardrb --fix
```

If auto-fix doesn't resolve all issues, stop and report them.

## Step 7: Update Version File

Edit `lib/ruby_llm/agents/core/version.rb` to update the VERSION constant to the new version.

## Step 8: Update CHANGELOG.md

Read `CHANGELOG.md` to understand the existing format.

**Check if an unreleased entry already exists** for the new version (or a section at the top without a matching git tag). If it does:
- Update the version number in the header if needed (e.g., change `## [3.5.0]` to match the calculated version)
- Update the date to today's date (YYYY-MM-DD format)
- Verify the comparison link at the bottom exists and is correct

If NO unreleased entry exists, generate one:
1. Analyze commits since the last tag:
   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --oneline
   ```
2. Categorize changes into Added/Changed/Fixed/Breaking Changes sections
3. Add the new section at the top (after the header), following the existing format
4. Add the comparison link at the bottom:
   ```markdown
   [{new_version}]: https://github.com/adham90/ruby_llm-agents/compare/v{previous_version}...v{new_version}
   ```

Show the user the changelog entry and ask for confirmation before writing it.

## Step 9: Commit Changes

Stage and commit only the version and changelog files:

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && git add lib/ruby_llm/agents/core/version.rb CHANGELOG.md && git commit -m "Bump version to v{new_version}"
```

If the pre-commit hook fails, fix the issues (likely StandardRB), re-stage, and create a NEW commit (do NOT amend).

## Step 10: Release to RubyGems

Run the bundler release task which will:
- Build the gem
- Create a git tag (v{new_version})
- Push the tag to GitHub
- Push the gem to RubyGems.org

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && bundle exec rake release
```

If this fails due to missing credentials, inform the user they need to run `gem signin` first.

## Step 11: Create GitHub Release

Extract the changelog entry for `[{new_version}]` from `CHANGELOG.md` (everything between the version header and the next version header). Use it as the GitHub release notes:

```bash
gh release create v{new_version} --title "v{new_version}" --notes "$(cat <<'EOF'
{changelog_entry_content}
EOF
)"
```

This ensures the GitHub release always has meaningful, structured release notes matching the changelog.

## Step 12: Summary

Display a success summary:

> ## Release Complete!
>
> **Version**: v{new_version} ({bump_type} bump)
>
> **What was detected**:
> - {summary of version detection signals}
>
> **Links**:
> - RubyGems: https://rubygems.org/gems/ruby_llm-agents/versions/{new_version}
> - GitHub Release: https://github.com/adham90/ruby_llm-agents/releases/tag/v{new_version}
> - Changelog: https://github.com/adham90/ruby_llm-agents/blob/main/CHANGELOG.md
>
> **Next steps**:
> - Verify the gem is available: `gem fetch ruby_llm-agents -v {new_version}`
> - Announce the release if appropriate

---

## Error Handling

- **Tests fail**: Stop immediately, show failures, do not release
- **Linting fails**: Try auto-fix, if still fails stop and report
- **Git not clean**: Stop, ask user to commit/stash changes
- **Not on main**: Warn and ask for confirmation
- **RubyGems auth fails**: Instruct user to run `gem signin`
- **GitHub CLI not authenticated**: Instruct user to run `gh auth login`
- **Release task fails**: Show error, do not create GitHub release
- **No commits since last tag**: Warn user there's nothing to release
