---
name: impacted-specs
description: Use when you want to find which RSpec specs to run for locally changed code, including uncommitted changes. Refreshes the coverage map produced by the test_impact gem's GitHub Actions collect workflow, then runs `test-impact plan` to narrow the run down to the impacted specs. Triggers on requests like "run only the tests related to my changes", "which specs does this diff affect", "figure out the impacted specs", or "what should I run for the current changes".
license: MIT
---

# impacted-specs

This skill runs inside a **project that consumes the test_impact gem**. It determines which specs
to run from local changes, including uncommitted ones.

Prerequisites:
- `gh` CLI is authenticated
- The consuming project has the `test_impact` gem in its `Gemfile`
- That project runs a collect workflow in GitHub Actions that uploads the coverage map as an
  artifact named `test-impact-map`

## Steps

### 1. Refresh the base

Check `base` in `.test_impact.yml` (defaults to `origin/main`) and fetch the corresponding remote
branch:

```sh
git fetch origin main
```

Why: if the local `origin/main` is stale, the map's `commit_sha` fails the history reachability
check and the plan degrades to a full run (`all`).

### 2. Download the map (every time, auto-discovered)

Do not judge freshness even if a local map exists — **always download the latest artifact and
overwrite**. Do not depend on a specific workflow name:

```sh
run_id=$(gh api 'repos/{owner}/{repo}/actions/artifacts?name=test-impact-map&per_page=1' \
  --jq '.artifacts[] | select(.expired == false) | .workflow_run.id' | head -1)
rm -f .test_impact/map.json.gz
gh run download "$run_id" -n test-impact-map -D .test_impact
```

Notes:
- Test `expired` with an explicit `== false` comparison (`//` treats `false` as falsy and falls
  back to the right-hand side, so an `enabled // true` style check misjudges it).
- `gh run download` fails when a file of the same name already exists in the destination, so
  remove it first with `rm -f`.
- If `run_id` comes back empty (no artifact found), report to the user that the collect workflow
  is not set up and stop here.

### 3. Run plan

```sh
bundle exec test-impact plan --format json --include-uncommitted > /tmp/plan.json
```

`--format json` always exits 0. stdout is a single line of JSON:
`{"mode":"all|partial|none","spec_files":[...],"reason":null|"..."}`.
Diagnostics (mode / reason / spec_files count, etc.) go to stderr.

### 4. Interpret the result

- `mode: "partial"` → run only the selected specs:
  ```sh
  bundle exec rspec $(jq -r '.spec_files[]' /tmp/plan.json)
  ```
- `mode: "none"` → report to the user that there are no specs to run.
- `mode: "all"` → **do not run the full suite on your own.** Report that a full run is required
  along with `reason`, and ask the user how to proceed. Common `reason` values:
  - `uncovered file changed: <path>` — a new or uncollected file was changed
  - `no map available or backend invalid` — the map is missing or unusable

## Caveats

- If `.test_impact/` is not in the consuming project's `.gitignore`, the map itself is treated as
  an untracked new file and triggers a full run.
- In a shallow clone, merge-base computation fails and the plan degrades to a full run.
- `--include-uncommitted` includes staged / unstaged / untracked changes in the diff, but never
  modifies repository state (read-only).
