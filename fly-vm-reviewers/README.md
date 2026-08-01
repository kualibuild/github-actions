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
| `reviewers` | no | `scojosmith` | Space-separated GitHub logins to request |
| `token` | no | `${{ github.token }}` | Needs `pull-requests: write` |

## Behavior notes

- **Section-based detection.** The whole `[[vm]]` table is extracted and
  compared, rather than grepping for key names. Both schemas in use are covered
  (`cpu_kind`/`cpus`/`memory`, and `size`), and it stays correct in files where
  `[[vm]]` is not the last block.
- **One request per reviewer.** GitHub rejects an entire batched review request
  if any single login lacks repo access, which would leave the PR with no
  reviewers at all. Each is requested separately; failures log a warning and
  the rest still go through.
- **Skips the PR author.** GitHub rejects a review request naming the author.
- **Skips already-pending reviewers**, so pushing to a PR doesn't re-request.

## Reviewers

Reviewers must have at least read access to the repo, or GitHub rejects the
request. To change the roster, edit the `reviewers` default in `action.yml` —
callers pick it up automatically.
