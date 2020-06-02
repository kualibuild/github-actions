const core = require('@actions/core')
const github = require('@actions/github')
const axios = require('axios')

const { wrap, headers } = require('../utils')

wrap(async () => {
  const { actor, workflow: wf, sha, payload } = github.context
  const { html_url: base, name: repo } = payload.repository
  const steps = core.getInput('steps').split('|')
  const info = [
    { label: 'Repo', url: base, value: repo },
    { label: 'Author', url: `https://github.com/${actor}`, value: actor }
  ]
  if (payload.pull_request) {
    const { html_url: prUrl, number: prNum } = payload.pull_request
    info.push({ label: 'PR', url: prUrl, value: `#${prNum}` })
  } else {
    const compareVal = payload.compare.split('/').pop()
    info.push(
      { label: 'Workflow', url: `${base}/commit/${sha}/checks`, value: wf },
      { label: 'Compare', url: payload.compare, value: compareVal }
    )
  }
  const body = {
    channel: process.env.SLACK_CHANNEL,
    blocks: [
      {
        type: 'context',
        elements: info.map(({ label, url, value }) => ({
          type: 'mrkdwn',
          text: `*${label}*   \n<${url}|${value}>`
        }))
      },
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: steps
            .map(title => `:gh-actions-pending: ${title}`)
            .join(' --> ')
        }
      },
      { type: 'divider' }
    ]
  }
  const resp = await axios.post(
    'https://slack.com/api/chat.postMessage',
    body,
    { headers: headers() }
  )
  core.exportVariable('SLACK_TS', resp.data.ts)
})
