#!/bin/sh
set -eu

# https://github.com/marketplace/actions/post-slack-message

data='{}'
data="$(echo '{}' | jq -M --arg TEXT "${INPUT_TEXT}" '.text = $TEXT')"

# https://api.slack.com/methods/chat.postMessage

curl ${INPUT_SLACK_WEBHOOK} \
  -X POST \
  -H "Content-type: application/json" \
  -d "$data"
