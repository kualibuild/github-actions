# Replicate

# Usage

Create a file in `.github/workflows/replicate.yaml`

```yaml
name: Replicate

on:
  schedule:
    - cron: '0 6 * * *'

jobs:
  replicate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1 # v1 is important, v2 breaks things for this
      - uses: kualibuild/github-actions/replicate@master
        with:
          token: ${{ secrets.KUALIBUILD_PROJECT_BOT_TOKEN }}
          target_repo: '' # org/repo
```
