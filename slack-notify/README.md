# Slack Notify Github Action

# Usage

First you need a bot user.

1. Go to [Your Apps](https://api.slack.com/apps) in slack and click on "Create
   New App". Give it a descriptive app name and select the workspace you'd like
   this to access.

1. Click on "Incoming Webhooks" and enable Incoming Webhooks. Add a new webhook
   at the bottom of that page by clicking "Add New Webhook to Workspace". You'll
   need to select a channel for the webhook. Copy that webhook url.

1. In Github in your repo settings page, create a new secret, call it something
   like `SLACK_WEBHOOK` (you can call it whatever you'd like, we'll reference it
   later).

Now configure your github action workflow:

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: kualibuild/github-actions/slack-notify@master
        with:
          slack_webhook: ${{ secrets.SLACK_WEBHOOK }}
          text: Got notified in slack
      - uses: kualibuild/github-actions/slack-notify@master
        if: ${{ failure() }}
        with:
          slack_webhook: ${{ secrets.SLACK_WEBHOOK }}
          text: Something went wrong
```
