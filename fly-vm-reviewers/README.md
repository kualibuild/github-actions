# Fly VM Reviewers

Requests review from the DevOps reviewers when a pull request changes the
`[[vm]]` block of a watched `fly.toml` — i.e. when it may affect infrastructure
capacity. Changes elsewhere in those files (env vars, service ports, statics)
are ignored.

## Usage

```yaml
name: Request infra reviewers
on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review]
    paths: ['fly.us.toml', 'fly.ca.toml']

jobs:
  vm-reviewers:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: kualibuild/github-actions/fly-vm-reviewers@master
        with:
          files: "fly.us.toml fly.ca.toml"
```

`fetch-depth: 0` is required — the action compares the `[[vm]]` block at the
PR base against the head, so both commits must be present.

The `paths:` filter is an optimization only; the action re-checks the `[[vm]]`
block itself and exits quietly when nothing capacity-related changed.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `files` | yes | — | Space-separated fly config paths to watch |
| `teams` | no | `devops` | Space-separated team slugs to request |
| `reviewers` | no | — | Space-separated GitHub logins, in addition to teams |
| `token` | no | `${{ github.token }}` | Needs `pull-requests: write` |

## Behavior notes

- **Section-based detection.** The whole `[[vm]]` table is extracted and
  compared, rather than grepping for key names. Both schemas in use are covered
  (`cpu_kind`/`cpus`/`memory`, and `size`), and it stays correct in files where
  `[[vm]]` is not the last block.
- **A team is requested as a unit.** Members who have not yet accepted their org
  invitation are simply absent from the request rather than causing it to fail,
  and they start being notified automatically once they join — no change here.
- **One request per reviewer**, so one bad login cannot take the others down
  with it. Failures log a warning and the rest still go through.
- **Success is read back from the response, not the exit code.** GitHub answers
  `200` and silently adds nobody when a login does not exist, so trusting the
  exit code would report success while requesting no one — the exact silent
  failure this action exists to prevent.
- **Skips the PR author.** GitHub rejects a review request naming the author.
- **Skips already-pending reviewers**, so pushing to a PR doesn't re-request.

## Reviewers

The team (or user) must have at least read access to the repo, or GitHub rejects
the request with `422 Reviews may only be requested from collaborators`.

Roster changes are made in GitHub — add or remove people from the `devops` team
and this action needs no edit at all. Only a change of *which* team is asked
requires touching the `teams` default in `action.yml`.
