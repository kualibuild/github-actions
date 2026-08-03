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
| `reviewers` | no | `scojosmith crerwin dlucas-clx` | Space-separated GitHub logins to request |
| `teams` | no | — | Space-separated team slugs, in addition to reviewers (see below) |
| `token` | no | `${{ github.token }}` | Needs `pull-requests: write` |

## Behavior notes

- **Section-based detection.** The whole `[[vm]]` table is extracted and
  compared, rather than grepping for key names. Both schemas in use are covered
  (`cpu_kind`/`cpus`/`memory`, and `size`), and it stays correct in files where
  `[[vm]]` is not the last block.
- **One request per reviewer**, so one bad login cannot take the others down
  with it. A reviewer with a pending org invitation, or without repo access,
  logs a warning; everyone else is still requested and notified normally.
- **Success is read back from the response, not the exit code.** GitHub answers
  `200` and silently adds nobody when a login does not exist, so trusting the
  exit code would report success while requesting no one — the exact silent
  failure this action exists to prevent.
- **Skips the PR author.** GitHub rejects a review request naming the author.
- **Skips already-pending reviewers**, so pushing to a PR doesn't re-request.

## Reviewers

A reviewer must have at least read access to the repo, or GitHub rejects that
one request with `422 Reviews may only be requested from collaborators`. The
loop continues, so the remaining reviewers are unaffected.

To change the roster, edit the `reviewers` default in `action.yml` — callers
pick it up automatically.

### Why not a team?

Requesting the `devops` team would move the roster into GitHub and need no
edits here. The `teams` input supports it, but it is off by default because
**`GITHUB_TOKEN` cannot request team reviewers** — teams are org-level and that
token is scoped to one repo. An org-scoped GitHub App token fails too unless the
App has org `Members: read`:

```
GET /orgs/<org>/teams/<slug>   -> 404 Not Found
POST .../requested_reviewers   -> 422 Could not resolve to a node with the
                                      global id 'T_kwDO...'
```

Enabling it therefore means either broadening an existing App's permissions or
standing up a dedicated one — a lot of machinery for moving a roster out of a
file. Enumerating logins needs no credential at all.
