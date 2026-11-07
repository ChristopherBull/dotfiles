# CI cost and runtime levers

Each lever: what it saves, the risk, and how to do it in GitHub Actions. Other CI systems
have equivalents (GitLab `rules:changes`, `interruptible`, `needs`; CircleCI path
filtering; Buildkite `if_changed`), so the reasoning carries over even where the YAML
doesn't.

## Contents

1. Don't run at all
2. Don't run twice (PR and main)
3. Expensive jobs only when relevant
4. Pay less per job
5. Stop runaway minutes
6. Caches
7. Bots and schedules
8. Runtime without extra cost
9. Things that look like savings but aren't

## 1. Don't run at all

**Triggers.** Run on `pull_request` and on `push` to the default branch only, not on every
branch push as well (that runs each PR commit twice). Set PR `types` explicitly if drafts
should skip the expensive jobs:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]
```

**Cancel superseded runs** on PRs, but not on main, where cancelling could stop a release
halfway:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

**Per-job path filters.** One cheap `changes` job (on the cheapest runner, with a sparse
checkout) works out what the change touches and sets outputs; every other job has
`if: needs.changes.outputs.<flag> == 'true'`. Don't use a workflow-level `on: paths:`
when checks are required, since a workflow that never starts leaves the check pending.
Get the files from the API rather than a deep clone:

```bash
set -o pipefail
if [ -n "$PR" ]; then
  files=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR/files" --jq '.[].filename') || files=
elif [ -n "$BEFORE" ] && [[ ! "$BEFORE" =~ ^0+$ ]]; then
  # The comparison lists at most 300 files; more means "check everything".
  files=$(gh api "repos/$GITHUB_REPOSITORY/compare/$BEFORE...$GITHUB_SHA" \
    --jq 'if (.files | length) >= 300 then error("too many") else .files[].filename end') || files=
fi
[ -n "$files" ] || { echo "::warning::Could not list the changed files; checking everything."; files=ALL; }
touches() { [ "$files" = ALL ] || grep -qE "$1" <<< "$files"; }
```

Third-party actions such as `dorny/paths-filter` do the same; a few lines of shell avoid
a dependency and are easy to stub-test locally. Map each job to the paths that really
affect it, including the workflow file itself and shared setup actions. When unsure,
include a path: a missed dependency is worse than a wasted run.

**Docs-only changes** should run only what checks docs (format, spelling, link checks).

## 2. Don't run twice (PR and main)

A PR is tested, merged, and the push to main tests the same thing again. When the merged
commit's **tree** equals the tree a passing PR run tested (a rebase or fast-forward of an
up-to-date branch, or a squash of one), the result can't differ.

Pattern (no merge queue needed):

1. On PRs, a final `passed` job (runs only when nothing failed or was cancelled) uploads a
   small artefact named `ci-passed-<tree SHA>` recording which suites ran
   (`unit=true` and so on). Coverage reports are uploaded as artefacts as usual.
2. On a push to main, the `changes` job looks it up:

   ```bash
   tree=$(git rev-parse 'HEAD^{tree}')
   run=$(gh api "repos/$GITHUB_REPOSITORY/actions/artifacts?name=ci-passed-$tree" \
     --jq '[.artifacts[] | select((.expired | not) and
       .workflow_run.head_repository_id == .workflow_run.repository_id)][0].workflow_run.id // empty') || run=
   ```

   Only trust runs from the same repository (not forks). The job needs `actions: read`.
3. If found, skip every suite it ran, run only the ones it skipped (a draft, a path filter),
   and have the coverage job download that run's coverage artefacts and upload them for
   main's commit. If not found, run everything.
4. Make the release job's `if:` tolerate skipped needs:
   `!cancelled() && !contains(needs.*.result, 'failure') && !contains(needs.*.result, 'cancelled')`.
   Do the same for **every** job downstream of one that can now be skipped, however far
   down the chain: without an `if:` of its own, a job is skipped when any ancestor was.
   List each job's `needs` and `if` and check every path.

Risks: the tree must be identical; a merge commit, or a branch behind main, gets a new
tree and simply runs in full (safe). Keep artefact retention short (a few days). Tell the
person to merge while the branch is up to date. A merge queue, where available, is the
built-in alternative.

If the person requires coverage on every main commit, reuse (don't drop) the PR's
coverage. Don't skip reporting just because tests were skipped.

## 3. Expensive jobs only when relevant

- Build images, installers and other long artefacts only when their inputs change, and
  only after the cheap checks pass (`needs:`).
- To keep "only after the checks pass" while moving a big job into its own file, make it a
  reusable workflow (`on: workflow_call`) and call it as a job:
  `kiosk: { needs: [checks], if: ..., uses: ./.github/workflows/kiosk.yml }`. A separate
  `workflow_run` workflow can't wait on individual jobs and is harder to require.
- Run the costliest variants (reproducibility double-builds, full browser matrices, every
  OS) on main or when their inputs change, if the person agrees the PR can run less.
- Skip expensive suites on draft PRs; run them on `ready_for_review`.

## 4. Pay less per job

- **Billing rounds each job up to a whole minute**, and every job pays checkout, setup and
  install. Merge checks that take less time than their setup into one job. Give each step
  `if: ${{ !cancelled() && steps.setup.outcome == 'success' }}` so every check still runs
  and reports after one fails.
- **Cheaper runners.** GitHub's `ubuntu-slim` (one vCPU, a container) costs much less per
  minute than `ubuntu-latest` (two vCPUs). Put light, single-threaded jobs there: lint,
  format, spelling, small scripts, the `changes`, aggregate and coverage-upload jobs. Keep
  CPU-heavy tests, browsers and builds on standard runners; check that the job doesn't
  need Docker, privileged containers or more memory. Check current pricing:
  <https://docs.github.com/en/billing/reference/actions-runner-pricing>.
- **Set up only what the job uses.** Give shared composite setup actions inputs (such as
  `python: false`, `kiosk: false`) so a job doesn't install toolchains it never touches.
- **Container images** with tools preinstalled (such as Playwright's image pinned to the
  locked version) can replace slow installs.

## 5. Stop runaway minutes

- `timeout-minutes` on every job, about two to three times its normal duration (GitHub's
  default is 360).
- `timeout-minutes` on long steps, and `timeout` on network calls inside steps: apt
  (`-o Acquire::http::Timeout=30`), curl (`--max-time`, `--retry`), mirrors. For
  retried long commands, give each try its own limit
  (`timeout --kill-after=1m 25m cmd`) so one stalled try can't take the whole job.
- `fail-fast` in matrices where one failure makes the rest pointless.

## 6. Caches

- **Save only when the content changed.** Split `actions/cache` into `restore` and
  `save`; fingerprint the cached files before and after the job, hashing only the files
  that matter (for example `find dir -type f -name '*.deb' -printf '%P %s\n' | sort |
  sha256sum`), and save only if the fingerprint changed. A fingerprint that includes logs,
  lock files or timestamps always changes, so it saves every run, fills the 10 GB repo
  limit and evicts useful caches.
- Restore keys with a stable prefix so a partial hit still helps.
- Watch `gh cache list --sort size_in_bytes`; caches unused for 7 days expire.
- Don't cache what's faster to download than to restore.

## 7. Bots and schedules

- **Dependabot**: `interval: monthly` (or weekly) instead of daily; `groups:` to batch
  updates into one PR; `rebase-strategy: disabled` so every push to main doesn't rebase
  and re-run every open Dependabot PR (comment `@dependabot rebase` when needed).
  Security updates still arrive on their own schedule.
- **Scheduled workflows**: as rarely as is useful, and skip when nothing changed since the
  last scheduled run.

## 8. Runtime without extra cost

Faster feedback is worth having when it costs roughly the same:

- Order work so failures surface early: cheap checks first, expensive jobs `needs:` them
  (this saves cost too).
- Run independent jobs in parallel instead of in a chain, when they'd run anyway.
- Shorten the critical path: the slowest job sets the wall clock, so speed that one, not
  the short ones.
- **Sharding and workers trade cost for speed.** Each shard pays setup again; more workers
  in a job compete for its vCPUs. Measure on CI before and after, look at billed minutes
  as well as wall clock, and revert if the saving isn't real. Tests with wall-clock
  budgets can fail under parallel load.
- Bigger runners cost proportionally more per minute; they only pay off when the job
  scales nearly linearly with cores.

## 9. Things that look like savings but aren't

- Dropping a check people rely on, or running it only on main so failures land after
  merge.
- `on: paths:` on a workflow whose checks are required (it leaves PRs blocked).
- Filters that fail closed when the API errors.
- Caching everything (saves can take longer than the work).
- Retrying flaky tests automatically in CI: it hides the flake and bills each retry. Fix
  the flake; re-run failed jobs by hand in the meantime.
