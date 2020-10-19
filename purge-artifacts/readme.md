# Purge Artifacts

Every time we run tests we upload the resulting test artifacts. Github only gives us 2GB of action storage and we blow past that pretty quickly as those artifacts add up. This action deletes artifacts older than the configured expiration.

credit: https://github.com/kolpav/purge-artifacts-action

## Usage

```
env:
  SLACK_TOKEN: ${{ secrets.SLACK_TOKEN }}
  SLACK_CHANNEL: ${{ secrets.SLACK_CHANNEL_ID }}
jobs:
  delete-artifacts:
    runs-on: ubuntu-latest
    steps:
      - uses: kualibuild/github-actions/purge-artifacts@master
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          # 1 week
          expires: 604800000
```
