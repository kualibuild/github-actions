# Superseded Guard

Stops a deploy job from shipping old code. Before deploying, it checks whether
the deploy branch has moved past this run's commit **in files that matter to
the deploy**:

- **Still current** → `deploy=true`, the deploy proceeds.
- **Superseded, first attempt** → `deploy=false` and a warning. This is the
  normal case when pushes queue up: the newest run deploys instead.
- **Superseded, re-run** → the step fails. "Re-run" on an old run rebuilds and
  deploys *that run's* commit, not the deploy branch tip, so it would
  silently roll production back.

## Usage

```yaml
on:
  push:
    branches: [main]
    paths: ["grafana/**"]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: guard
        uses: kualibuild/github-actions/superseded-guard@master
        with:
          paths: |
            grafana/**
      - if: steps.guard.outputs.deploy == 'true'
        run: ./deploy.sh
```

Gate every deploying step after the guard with
`if: steps.guard.outputs.deploy == 'true'`. A composite action cannot skip the
caller's remaining steps on its own.

Steps that already have a condition need the guard added to it, e.g.
`if: ${{ steps.guard.outputs.deploy == 'true' && !cancelled() && ... }}`.

Give `paths` and `paths-ignore` one bare glob per line, as above. The YAML list
form (`- grafana/**`) and quoted patterns (`"grafana/**"`) are rejected with an
error rather than silently matching nothing.

The deploy branch is the repository's primary branch unless you set `branch`.
Set it when the workflow deploys from somewhere else, such as a release branch:

```yaml
      - id: guard
        uses: kualibuild/github-actions/superseded-guard@master
        with:
          branch: release
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `branch` | no | primary branch | Branch this run must still match; set it when deploying from a non-primary branch. `refs/heads/` is optional |
| `sha` | no | checked-out commit | Commit being deployed; set it if the deploy ships something other than what's checked out |
| `paths` | no | `**` | Deployable globs, one per line, matched like `on.push.paths` (in order; leading `!` excludes) |
| `paths-ignore` | no | — | Globs that never count, one per line, matched like `on.push.paths-ignore` (no `!`) |
| `fail-on-rerun` | no | `true` | Fail a superseded re-run instead of only warning |
| `working-directory` | no | `.` | Where the repo is checked out, if `actions/checkout` used `path:` |

## Outputs

| Output | Description |
|--------|-------------|
| `deploy` | `"true"` when the deploy should proceed |
| `tip` | The deploy branch tip SHA compared against (empty when the guard did not apply) |

## Behavior notes

- **Mirror the workflow's path filters.** Copy `on.push.paths` into `paths`
  and `on.push.paths-ignore` into `paths-ignore`. If the guard counts more files
  than the trigger does, a newer commit that touches only those extra files
  makes this run stand down — while that commit's own run is filtered out, so
  nothing deploys the real change. If it counts fewer, a superseded re-run can
  roll those files back.
- **Matches patterns the way GitHub does.** `*` stays within a directory, `**`
  crosses them (`**.js` is any `.js` file at any depth, `**/README.md` includes
  the root one), `?` and `+` apply to the preceding character, and `paths` is
  read in order: a later `!` pattern excludes a match, a later plain pattern
  includes it again. As in GitHub, `paths` needs at least one pattern without
  `!`, and `paths-ignore` takes no `!` patterns. Either mistake is an error.
  Patterns that match no file in the deployed commit get a warning.
- **Must be a step, not a separate job.** "Re-run failed jobs" reuses a
  succeeded job's outputs instead of running it again, so a guard job would
  never re-check. As a step it re-checks on every attempt.
- **Compares against the deploy branch.** That's the `branch` input if set,
  otherwise the primary branch, read from the event payload or, when the event
  doesn't carry it, from the remote (`git ls-remote --symref origin HEAD`). So
  `main` and `master` repos need no configuration. A deploy dispatched from any
  other branch is held to the same standard: it proceeds only if it matches the
  deploy branch in the deployable paths. With no `branch`, this mirrors
  pdf-api's original guard, which hard-coded `master`.
- **Compares what's checked out.** The deployed commit is `HEAD` of the
  checkout, so a `ref:` checkout (e.g. a `workflow_run` deploy of `head_sha`,
  where `GITHUB_SHA` is the branch tip) is compared correctly. Set `sha` if the
  deploy ships something else.
- **Compares trees, not history.** It diffs the deployed commit against the
  deploy branch tip, limited to the deployable paths. Newer commits that net
  to no change in those paths (a change and its revert) don't supersede the
  run. A deploy branch force-pushed *behind* this commit does. A file moved out
  of the deployable paths counts as a change.
- **Leaves the clone as it found it.** It reads the tip with `git ls-remote`,
  and fetches the tip's objects only when they're missing and a diff is needed,
  keeping the clone's depth: a shallow checkout stays shallow and a
  `fetch-depth: 0` checkout keeps its full history for later steps.
- **Needs `actions/checkout`'s persisted credentials.** Reading and fetching
  from `origin` uses them, so `persist-credentials: false` makes the guard fail
  on a private repository.
- **Only guards branch runs.** `pull_request` runs and tag runs always get
  `deploy=true`: a merge ref or a tag can't be superseded in this sense.
- **Pair it with a queueing `concurrency` group** (`cancel-in-progress: false`)
  so two deploys never run at once. The guard covers re-runs and queued
  backlogs; concurrency covers overlap.

## Testing

`superseded-guard/test.sh` runs `run.sh` against throwaway repos (a local bare
repo as `origin`, the GitHub env vars set by hand). It needs only bash and git:

```sh
superseded-guard/test.sh
```
