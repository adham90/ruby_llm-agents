---
description: Release a new version of ruby_llm-agents to RubyGems and GitHub
argument-hint: <patch|minor|major> [release notes]
allowed-tools: Bash, Read, Edit, Glob, Grep, Write, AskUserQuestion
---

# Ruby LLM Agents Release Command

You are automating a gem release for `ruby_llm-agents`. The user has provided: `$ARGUMENTS`

## Step 1: Parse Arguments and Validate

Parse the arguments to extract:
- **Bump type**: First argument must be `patch`, `minor`, or `major`
- **Release notes**: Optional remaining arguments (if any)

If no bump type is provided or it's invalid:
1. Read the current version from `lib/ruby_llm/agents/version.rb`
2. Show the user all three options with calculated versions:
   > Current version: **{current_version}**
   >
   > - `patch` → **{major}.{minor}.{patch+1}** (bug fixes, small changes)
   > - `minor` → **{major}.{minor+1}.0** (new features, backwards compatible)
   > - `major` → **{major+1}.0.0** (breaking changes)
   >
   > Which version bump type?
3. Use `AskUserQuestion` to let the user pick

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

If not on `main` branch, warn the user and ask if they want to continue.
If there are uncommitted changes, stop and ask the user to commit or stash them.

## Step 3: Calculate New Version

Read the current version from `lib/ruby_llm/agents/version.rb`.

The version format is `MAJOR.MINOR.PATCH`. Calculate the new version:
- `patch`: Increment PATCH (e.g., 0.4.0 → 0.4.1)
- `minor`: Increment MINOR, reset PATCH to 0 (e.g., 0.4.0 → 0.5.0)
- `major`: Increment MAJOR, reset MINOR and PATCH to 0 (e.g., 0.4.0 → 1.0.0)

Display to user:
> "Version bump: **{current_version}** → **{new_version}** ({bump_type})"
>
> "Do you want to proceed with this release?"

Wait for explicit user confirmation before continuing.

## Step 4: Run Tests

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && bundle exec rake spec
```

If tests fail, stop immediately and report the failures. Do not proceed with the release.

## Step 5: Update Version File

Edit `lib/ruby_llm/agents/version.rb` to update the VERSION constant to the new version.

## Step 6: Update CHANGELOG.md

Read `CHANGELOG.md` to understand the format.

If the user provided release notes, use them. Otherwise:
1. Show recent commits since the last tag:
   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --oneline
   ```
2. Ask the user to provide release notes or confirm auto-generation

Add a new section at the top of the changelog (after the header), following this format:

```markdown
## [{new_version}] - {YYYY-MM-DD}

### Added
- {features}

### Changed
- {changes}

### Fixed
- {fixes}
```

Also add the comparison link at the bottom of the file:
```markdown
[{new_version}]: https://github.com/adham90/ruby_llm-agents/compare/v{previous_version}...v{new_version}
```

## Step 7: Commit Changes

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && git add lib/ruby_llm/agents/version.rb CHANGELOG.md && git commit -m "Bump version to v{new_version}"
```

## Step 8: Release to RubyGems

Run the bundler release task which will:
- Build the gem
- Create a git tag (v{new_version})
- Push the tag to GitHub
- Push the gem to RubyGems.org

```bash
cd /Users/adhameldeeb/dev/ruby_llm-agents && bundle exec rake release
```

If this fails due to missing credentials, inform the user they need to run `gem signin` first.

## Step 9: Create GitHub Release

Always use the changelog entry from Step 6 as the GitHub release notes. Extract the content for the `[{new_version}]` section from `CHANGELOG.md` (everything between the version header and the next version header) and pass it via a HEREDOC:

```bash
gh release create v{new_version} --title "v{new_version}" --notes "$(cat <<'EOF'
{changelog_entry_content}
EOF
)"
```

This ensures the GitHub release always has meaningful, structured release notes matching the changelog.

## Step 10: Summary

Display a success summary:

> ## Release Complete!
>
> **Version**: v{new_version}
>
> **Links**:
> - RubyGems: https://rubygems.org/gems/ruby_llm-agents/versions/{new_version}
> - GitHub Release: https://github.com/adham90/ruby_llm-agents/releases/tag/v{new_version}
>
> **Next steps**:
> - Verify the gem is available: `gem fetch ruby_llm-agents -v {new_version}`
> - Announce the release if appropriate

---

## Error Handling

- **Tests fail**: Stop immediately, show failures, do not release
- **Git not clean**: Stop, ask user to commit/stash changes
- **Not on main**: Warn and ask for confirmation
- **RubyGems auth fails**: Instruct user to run `gem signin`
- **GitHub CLI not authenticated**: Instruct user to run `gh auth login`
- **Release task fails**: Show error, do not create GitHub release

## Prerequisites Check

Before starting, verify these are available:
```bash
which gem && which gh && which bundle
```

If any are missing, inform the user what needs to be installed.
