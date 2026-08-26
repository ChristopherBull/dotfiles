---
name: upgrade-dev-deps
description: Use when upgrading dev dependencies (or any dependency batch) in a project's package manifest — grouping version bumps into reviewable commits, checking changelogs for breaking changes, measuring audit impact before/after, and scoping correctly in a monorepo or a single subfolder.
---

# Upgrading Dev Dependencies

## Overview

Bulk "check what's outdated" + one giant install produces an unreviewable
diff and hides which package broke what. Upgrade in small,
conceptually-grouped, individually-tested, individually-committed steps
instead — any regression bisects to one commit. Examples use npm; the
process applies to any package manager (see Other Ecosystems).

## When to Use

- Asked to update/bump dev dependencies, or clear an outdated list.
- Asked to check audit/vulnerability impact of an upgrade.
- Any task touching multiple unrelated packages in one manifest.

## Step 0: Scope the Work

1. **Detect monorepo vs. standard repo**: root `workspaces` field,
   `pnpm-workspace.yaml`, `lerna.json`/`nx.json`/`turbo.json`/`rush.json`, a
   Cargo `[workspace]`, or multiple manifests under subfolders.
2. **Determine the requested scope**: whole repo, one workspace/package, or
   one manifest/subfolder. In a monorepo, if the request doesn't say, ask
   before starting rather than assuming repo-wide — state the resolved
   scope back (e.g. "scoping to `packages/api` only").
3. Everything below stays inside that scope — never touch a manifest or
   lockfile outside it.

## Process

1. **Baseline.** Check outdated packages and run an audit for every
   manifest/lockfile in scope. Save vulnerability counts by severity to
   diff against at the end.
2. **Group by tool/ecosystem, not alphabetically** — all of one tool's
   packages per commit (e.g. all `@commitlint/*`). Peer-dependent packages
   move together in the same group. In a monorepo with independent
   per-workspace lockfiles, the same tool at different versions in
   different workspaces is a separate group per workspace; a shared/hoisted
   lockfile can often be grouped once across the tree.
3. **Per group, on any major bump:** read the changelog for the actual
   range crossed, not just "latest" — breaking config/CLI changes, raised
   minimum runtime, rule/behavior changes in linters. "Changelog says safe"
   isn't enough — it misses breaks in the package's *consumer*, not the
   package itself (see Common Mistakes).
4. **Install the group, scoped**, then run the narrowest relevant test,
   then the broader suite. In a monorepo, use the workspace filter (`npm
   test -w <pkg>`, `pnpm --filter <pkg> test`, `turbo run test
   --filter=<pkg>`) rather than the whole tree, unless the tool is shared
   root tooling. Check the diff — installing without an explicit dev flag
   can land a package in the wrong dependency section.
5. **Commit immediately per group**, before starting the next:
   `chore(deps): update <group>`, scoped to the workspace/subfolder if not
   repo-wide. Verify against the repo's actual release-automation config
   that a `chore` commit won't trigger a release — don't assume.
6. **Blocked major bump?** Don't force it past a peer-dependency mismatch
   further up the chain — pin to the latest compatible version, note why,
   move on.
7. **Finish with a non-forcing audit-fix pass** for a lockfile-only sweep
   of transitive vulnerabilities, re-test, commit separately.
8. **Report before/after vulnerability counts by severity.** Repo-wide
   monorepo upgrade: per-workspace numbers plus a rollup total. Scoped run:
   that scope's numbers, and name what was left untouched.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Trusting "no breaking changes" from a changelog alone | Run the tool against its real config after installing — a consumer can break even when the upgraded package's own changelog is clean |
| Bundling unrelated packages in one commit | One conceptual group per commit |
| Treating a failing test as a regression | Re-run once before blaming the upgrade; compare against the pre-upgrade version if still unsure |
| Running the full local test script when it fails oddly | Check what CI actually runs step-by-step before assuming a real bug |
| Installing at the repo root in a workspace repo | Use the workspace/filter flag, or it touches the wrong manifest |
| Upgrading the whole monorepo when only one package was asked for | Confirm scope in Step 0 and stay inside it |

## Other Ecosystems

| Ecosystem | Outdated | Audit | Install pinned |
|---|---|---|---|
| npm | `npm outdated` | `npm audit` | `npm install pkg@x.y.z` |
| pnpm | `pnpm outdated` | `pnpm audit` | `pnpm add pkg@x.y.z` |
| Yarn | `yarn outdated` | `yarn npm audit` | `yarn add pkg@x.y.z` |
| Poetry/pip | `poetry show --outdated` | `pip-audit` | `poetry add pkg@x.y.z` |
| Cargo | `cargo outdated` | `cargo audit` | `cargo add pkg@x.y.z` |
| Bundler | `bundle outdated` | `bundle audit` | `bundle add pkg -v x.y.z` |
| Go modules | `go list -m -u all` | `govulncheck ./...` | `go get pkg@x.y.z` |

## Worked Example

Standard npm repo, whole-repo upgrade: 20 devDependencies across 11
commits, audit vulnerabilities 50→17 (5 critical→0). Caught two issues
changelog research missed: a linter's major version dropping a transitive
dependency its own config statically imported, and a changelog-preset major
bump requiring a newer peer package than the release-automation tool
(already latest) actually shipped — both found only by running the
consuming tool, not by reading changelogs.
