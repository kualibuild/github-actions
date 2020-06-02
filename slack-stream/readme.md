# Slack Stream

Get awesome slack reporting for linear workflows.

Caveats: Must be a linear workflow run in a single job

## Usage

First make sure to add all of the emoji in `_emoji\*.png` to your slack.

Then must generate a slack bot user with the `chat:write` and `channels:history` scopes.

All of these steps rely on `SLACK_TOKEN` and `SLACK_CHANNEL` being set as environment variables.

This feature is comprised of 5 actions. Configure the create at the beginning of your job. Put the start/finish around each step of your job. Lastly, make sure to report errors/cancellation at the end.

Also, make sure you call start/finish for every step you've defined. Here's an example:

```
env:
  SLACK_TOKEN: ${{ secrets.SLACK_TOKEN }}
  SLACK_CHANNEL: ${{ secrets.SLACK_CHANNEL_ID }}
jobs:
  build:
    name: 'Build'
    runs-on: ubuntu-latest
    steps:
      - uses: kualibuild/github-actions/slack-stream/create@master
        with:
          steps: 'Build project|Deploy it somewhere'

      - uses: kualibuild/github-actions/slack-stream/start@master
      - run: ./build
      - uses: kualibuild/github-actions/slack-stream/finish@master

      - uses: kualibuild/github-actions/slack-stream/start@master
      - run: ./deploy
      - uses: kualibuild/github-actions/slack-stream/finish@master

      - if: ${{ failure() }}
        uses: kualibuild/github-actions/slack-stream/error@master
      - if: ${{ cancelled() }}
        uses: kualibuild/github-actions/slack-stream/cancel@master
```
