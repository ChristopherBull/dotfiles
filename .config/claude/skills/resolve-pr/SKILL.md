---
name: resolve-pr
description: Automates getting a GitHub pull request to a clean, mergeable state — creates the PR if one doesn't already exist, waits for CI, diagnoses and fixes any failing checks, addresses and resolves reviewer comments, batches fixes into a single push per pass to save CI usage, and repeats until CI is green and no comments remain outstanding. Use this whenever the user asks to open a PR and get it ready, resolve or fix CI failures on a PR, address or resolve PR review comments, or says things like "resolve this PR", "get this PR green", "sort the CI out on this branch", "fix the review comments", "push this and make it mergeable". Requires the GitHub CLI (`gh`), authenticated against the repo.
---

# Resolve PR

Runs the full PR lifecycle end-to-end: fix, commit, batch-push, re-check, repeat — without pushing after every individual fix, which burns CI minutes for no reason.

## Before starting

- Check `gh auth status` and that the working tree is on a feature branch (never `main`/`master` — if it is, stop and ask).
- Set an iteration cap of 5 passes through the loop below. If CI is still red or comments are still open after 5 passes, stop and report back rather than continuing indefinitely — that pattern usually means the fix approach itself is wrong, not that one more try will do it.

## Step 1 — Create the PR (or find the existing one)

```
gh pr view --json number,url 2>/dev/null || gh pr create --fill
```

`--fill` pulls the title/body from the branch's commits. If the commit history is messy, write a clean title and short body yourself instead of relying on it.

## Step 2 — Wait for CI using the `Monitor` tool

Never block the session on `gh pr checks --watch`, and never chain a `sleep` in front of a status check — foreground sleeps are blocked and the call gets rejected. Use `Monitor`, which runs a command in the background and feeds each line of its output back as an event, so the session stays usable while CI runs.

Don't put `--watch` inside the monitor either. Blocking isn't the objection there, since the monitor backgrounds it anyway — the objection is output shape. `--watch` reprints the whole check table every refresh, and the monitor turns each of those lines into an event. A ten-check pipeline running twenty minutes is hundreds of events all saying nothing has changed. The loop below prints one line, once.

Give it a script that stays quiet while checks are pending and prints once, when they settle. `gh pr checks` exits 8 while anything is still running, 0 when all pass, 1 when something failed, so the exit code is the whole state machine:

```bash
while :; do
  gh pr checks <number> >/dev/null 2>&1; code=$?
  [ "$code" -eq 8 ] || break
  sleep 30
done
echo "CI settled (exit $code)"
gh pr checks <number>
```

Set the inputs deliberately:

- `description`: specific, e.g. `CI status for PR #33`. It labels every notification, which matters once more than one monitor is live.
- `timeout_ms`: the default is 5 minutes, which most pipelines outrun. Set roughly twice the pipeline's usual duration; the ceiling is 1 hour (`3600000`).
- Leave `persistent` unset. This watch should end when CI settles, not run to the end of the session.

Rules that keep the watch well behaved:

- Poll no faster than every 30s — it's a remote API call and rate limits apply.
- Silence means "nothing to report". Print only on a state change, never once per poll; every line costs context.
- Suffix anything that can fail transiently with `|| true` so one network blip doesn't kill the watch.
- If you pipe through a filter, use `grep --line-buffered`, or pipe buffering will hold events back for minutes.
- Don't use `pgrep -f "<cmdline>"` as the loop condition — the monitor's own bash process matches the pattern and the loop never exits.
- Cancel the monitor with `TaskStop` as soon as the pass is done. A forgotten monitor burns context for nothing.

If `Monitor` isn't available (it needs Claude Code v2.1.98+, and it's absent on Bedrock, Google Cloud's Agent Platform and Microsoft Foundry), fall back to running `gh pr checks <number> --watch --fail-fast --interval 30` as a Bash call with `run_in_background: true`. `--watch` is fine here precisely because background Bash isn't an event stream: the output sits in a buffer and only costs context when you go and read it, so the redraws are harmless. `--fail-fast` stops the watch on the first failure instead of waiting out the rest of the pipeline.

## Step 3 — The fix-and-batch loop

Repeat until the stop condition in (d) is hit:

**a. Check what's outstanding.**
```
gh pr checks <number>
```
plus the PR's unresolved review threads (query in `references/github-graphql.md` — resolved/already-replied threads don't block, so filter for `isResolved: false`).

**b. If checks are all green and there are no unresolved threads, stop — the PR is done.**

**c. Otherwise, work through everything outstanding in this pass:**
- For each failing check: pull its logs (`gh run view <run-id> --log-failed`), diagnose the cause, make the fix, and commit it on its own — one commit per distinct fix, with a message describing what it addresses. Don't push yet.
- For each unresolved review thread: make the requested change if it's actionable, or write a reply if it's a question or needs discussion rather than a code change. Commit any code change separately. Reply to the thread and resolve it (mutation in `references/github-graphql.md`) once it's addressed. If a comment raises a genuine disagreement or something you're not confident about, reply with your reasoning but leave the thread unresolved and flag it in the final report — don't resolve your way past a comment you haven't actually settled.
- Keep commits scoped to one fix each. That's what makes the batched push reviewable and, if something's wrong, revertable without unpicking a giant commit.

**d. Push once, after everything in this pass is committed.**
```
git push
```
Never push after each individual commit — that defeats the point of batching. Never force-push without asking the user first, even if rewriting history seems tidy.

Then go back to Step 2 to wait for the new run triggered by this push, then back to (a).

**Stop and report to the user, rather than looping further, if:** the PR is clean (success); the 5-pass cap is hit; or a check is failing for a reason that isn't a code problem you can act on (flaky infra, missing secrets/permissions, external service down) — don't keep committing speculative fixes against something you can't actually diagnose.

## Step 4 — Final report

State the PR URL, final check status, how many passes it took, and anything deliberately left open (unresolved threads, checks you couldn't fix) so nothing is silently dropped.

## Notes

- Optional second monitor: while working through a pass, you can watch for reviewer comments arriving mid-flight by polling `gh api "repos/<owner>/<repo>/pulls/<number>/comments?since=$last"` on a 60s cycle and printing only new bodies. Only worth starting if a review is actively in progress — otherwise it's noise.
- This skill never merges the PR — it only gets it ready. Merge only if the user explicitly asks for that separately.
- Resolving a review thread and replying to inline comments are GraphQL/REST calls, not something `gh pr` wraps directly — see `references/github-graphql.md` for the exact commands.
