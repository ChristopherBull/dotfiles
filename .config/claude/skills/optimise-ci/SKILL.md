---
name: optimise-ci
description: >-
  Review and optimise CI pipelines (GitHub Actions first, the same principles elsewhere)
  so they still do everything they must, then cost as little as possible, then run as fast
  as they can without costing noticeably more. Measures billed runner-minutes before and
  after, cuts runs that repeat or needn't happen (path filters, docs-only changes, the
  pull request and main pushes testing the same tree, Dependabot churn), merges tiny jobs,
  moves light jobs to cheaper runners, gates expensive builds, fixes caches that save
  every run, and adds timeouts so hung steps can't burn hours. Use whenever someone asks
  to make CI cheaper or faster, says CI costs too much or uses too many minutes, asks to
  review or tidy a workflow file (.github/workflows/*.yml, .gitlab-ci.yml and so on),
  wonders why CI runs twice, or hits Actions billing or cache limits, even if they don't
  say "optimise".
---

# Optimise CI

The goal, in strict priority order:

1. **Do what CI must do.** Every check that protects the project keeps running, and
   everything downstream that relies on CI (required status checks, releases, coverage
   reports, published artefacts, signed builds) keeps working. A cheaper pipeline that
   lets a broken change through costs far more than it saves.
2. **Then cost.** Fewer billed runner-minutes. On hosted runners that is usually what the
   bill is made of, and most CI spend is waste: work that didn't need to run, ran twice,
   or ran on a bigger machine than it needed.
3. **Then runtime.** Faster feedback, but only where it doesn't add meaningful cost.
   Parallelism usually costs money (every extra job pays its own start-up and setup), so
   a speed-up has to be measured against the minutes it adds.

When the two conflict, say so and let the person choose; don't quietly trade one for the
other.

## Workflow

### 1. Learn what must be kept

Read every workflow, the composite actions and reusable workflows they call, and the
repo's docs on CI, releases and contributing. Then list, before changing anything:

- what each job protects (lint, types, unit, browser, build, release, coverage, security);
- what consumes CI's results: required status checks or rulesets, merge queues, release
  jobs, coverage services, deploys, badges;
- how the repo merges (merge commit, squash, rebase) and whether branch protection exists.
  `gh api repos/{owner}/{repo}` gives the merge settings;
  `gh api repos/{owner}/{repo}/branches/main/protection` gives the protection (a 404 means
  none);
- whether the repo is private, since public repos on GitHub's standard runners are free
  and cost then matters much less than runtime.

Ask about anything non-negotiable that the files don't settle (for example "every commit
on main must report coverage"). It shapes the design, so ask before building.

### 2. Measure the current cost

Don't optimise from the YAML alone; the expensive parts are rarely the obvious ones.
Use `scripts/ci-cost.sh` (bundled with this skill) on a few recent runs of each kind (a
pull request, a push to main, a docs-only change, a Dependabot PR):

```bash
scripts/ci-cost.sh owner/repo RUN_ID [RUN_ID...]
```

It prints, per run, billed minutes by runner type (each job rounded up to the minute, as
GitHub bills), the actual minutes, the number of jobs and the wall clock. Also look at:

- how many runs each trigger causes per change (a PR run *and* a push run is double);
- per-job timings, to find the setup that costs more than the check;
- the slowest steps (`gh run view --job ID --log`; strip ANSI codes with
  `sed 's/\x1b\[[0-9;]*m//g'`) for installs, downloads and caches that save every time;
- the cache usage (`gh cache list`, and the 10 GB per-repo limit on GitHub);
- failures and re-runs: a flaky job that's re-run is billed again.

Keep these numbers: the final report compares against them.

### 3. Find the savings, cheapest first

Work through `references/levers.md`, which lists each lever with how it works, its risks
and the GitHub Actions patterns that implement it. In outline, by usual size of saving:

1. **Don't run at all**: precise triggers; skip drafts; per-job path filters, so a
   docs-only change runs only the docs checks; cancel superseded PR runs.
2. **Don't run twice**: a push to main that has exactly the tree a passing PR run tested
   needn't repeat it. Reuse that run's results and coverage, and run only what it skipped.
3. **Run expensive jobs only when relevant**: image builds, reproducibility checks and
   end-to-end suites behind file filters, and behind the cheap checks.
4. **Pay less per job**: merge jobs that take less time than their setup; put light jobs
   on cheaper runners; set up only what each job uses.
5. **Stop runaway minutes**: timeouts on every job, on long steps and on network
   downloads, so a hung mirror can't burn the default 6 hours.
6. **Stop needless saves**: caches that save only when their content changes, and only the
   files that matter.
7. **Fewer bot runs**: Dependabot less often, grouped, and not rebasing every open PR on
   each push to main.

Then look at runtime, keeping only changes that hold cost roughly level (see "Runtime" in
the levers file). Measure parallelism changes on CI itself: a laptop with many cores tells
you little about a two-vCPU runner.

### 4. Propose before acting

Give the person a numbered list: each change, what it saves (minutes per run and per
typical change, from the measurements), its risk and whether it needs a trial. Group
risky changes (fewer shards, more workers per job, dropping a check) separately and
recommend trying them alone. Let them pick. Don't apply changes they haven't agreed to.

### 5. Implement safely

- When the filter logic can't tell what changed (an API failure, too many files, a force
  push, a new branch), run everything. Failing open costs a few minutes; failing closed
  ships an unchecked change.
- Keep required status checks satisfiable. A job skipped by `if:` reports "Skipped", which
  satisfies a required check; a whole workflow skipped by `on: paths:` leaves the check
  pending forever. Prefer job-level conditions, or one aggregate job that is required.
- Least privilege: `permissions: {}` at the top level, each job opting in.
- Keep the docs that describe CI in step with it (contributing guides, ADRs, contracts).
- Lint the workflows (actionlint, zizmor, or the repo's own scanner) and test any shell
  filter logic locally with stubbed inputs: PR files, push ranges, drafts, API failures.
- Run `scripts/skip-audit.py` on the workflows
  (`uv run --with pyyaml --no-project python scripts/skip-audit.py .github/workflows/*.yml`).
  It lists jobs that would be skipped silently because a job before them was skipped,
  which becomes likely once jobs are conditional.
- Follow the repo's commit conventions. Small, separate commits for separate levers make
  a regression easy to find and revert.

### 6. Verify on CI, cheaply

CI minutes are the thing being saved, so iterate with care:

- batch fixes and push once per round; no repeat or soak runs to "make sure";
- cancel a run as soon as it has shown what you needed;
- check the logs for what each change was meant to do, not only for green ticks: the
  skipped jobs really skipped, the cache-save step was skipped, the reuse path was taken;
- some paths only run after merge (pushes to main, releases, schedules). Say so plainly,
  and check the first run after merge job by job: compare its job list with what should
  have run, since a job that is wrongly skipped still leaves the run green. If a check was
  missed, run it by hand from the run's artefacts where possible, and fix the condition.

### 7. Report the impact

Compare billed minutes, by runner type, wall clock and job count, for:

- the baseline (runs from before the change, of each kind);
- the change's own PR run(s);
- the first run(s) on main after merge.

Present it as a table, then the per-change estimate (for example "a typical PR plus its
merge: 250 → 105 runner-minutes"), what was traded (any runtime that got slower) and what
is still open. Give measured numbers as measured, and label estimates as estimates.

## Lessons worth remembering

- **Measure every parallelism change.** Running a Python suite with pytest-xdist on a
  two-vCPU runner saved nothing (4 m 49 s vs 4 m 43 s), and on a many-core laptop it broke
  tests with wall-clock budgets. It was reverted. Parallel workers inside one job compete
  for the same two vCPUs; shards are separate jobs, each paying setup.
- **Billing rounds up per job.** Seven 40-second jobs bill seven minutes; one job running
  all seven checks bills about two. Run each step with
  `if: ${{ !cancelled() && steps.setup.outcome == 'success' }}` so one failure doesn't
  hide the rest.
- **Skipping a job skips everything after it that has no `if:` of its own.** A job's
  implicit condition is `success()`, which fails when any job before it in the chain was
  skipped, not only its direct `needs`. Once one job can be skipped, give every job
  downstream an explicit condition such as
  `if: ${{ !cancelled() && needs.build.result == 'success' }}`. After making the main
  branch reuse a PR's image build, the reproducibility comparison two jobs later quietly
  stopped running; only reading the first post-merge run's job list showed it.
- **A separate workflow can't wait for another's jobs.** To build something only after
  the checks pass, use a reusable workflow (`workflow_call`) called from the main workflow
  with `needs:`, rather than a second workflow with `workflow_run`.
- **Hash what the cache holds, not the directory.** A cache-save condition that hashed
  every file under a directory (including logs and lock files) always saw a change. It
  re-saved 430 MB each run and pushed the repo past the 10 GB cache limit. Filtering to
  the package files fixed it.
- **The comparison API caps at 300 files.** Treat a capped list as "everything changed".
- **Pre-commit scanners need the files a workflow calls.** A hook that lints only the
  staged workflow fails when that workflow calls a reusable workflow that isn't in the
  snapshot.
- **Words in comments are spell-checked too.** Removing a word from the dictionary while a
  workflow comment still uses it fails the docs check. Running the spell checker on
  staged files in pre-commit catches this in a second.
