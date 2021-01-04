const core = require('@actions/core')
const axios = require('axios')

exports.wrap = fn => {
  try {
    fn().catch(error => {
      core.setFailed(error.message)
    })
  } catch (error) {
    core.setFailed(error.message)
  }
}

exports.headers = () => ({
  'Content-Type': 'application/json; charset=utf-8',
  Authorization: `Bearer ${process.env.SLACK_TOKEN}`
})

exports.getDuration = () => {
  const total = Math.round((+new Date() - process.env.SLACK_TIME) / 1000)
  const minutes = Math.floor(total / 60)
  const seconds = `${total - minutes * 60}`.padStart(2, '0')
  return minutes > 59 ? ' (> 1 hour)' : ` (${minutes}:${seconds})`
}

exports.getIndex = () => parseInt(process.env.SLACK_STEP_INDEX || '0')

exports.mapMessage = transform => text =>
  text
    .split(' --&gt; ')
    .map((value, i) => (exports.getIndex() === i ? transform(value) : value))
    .join(' --> ')

exports.update = transform => {
  const { SLACK_CHANNEL: channel, SLACK_TS: ts } = process.env
  return axios
    .get('https://slack.com/api/conversations.history', {
      params: { channel, latest: ts, limit: 1, inclusive: true },
      headers: {
        ...exports.headers(),
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    })
    .then(resp => {
      const blocks = resp.data.messages[0].blocks
      blocks[1].text.text = transform(blocks[1].text.text)
      return blocks
    })
    .then(blocks =>
      axios.post(
        'https://slack.com/api/chat.update',
        { channel, ts, blocks },
        { headers: exports.headers() }
      )
    )
    .catch(err => {
      console.error({ error })
    })
}
