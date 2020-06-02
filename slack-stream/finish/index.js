const core = require('@actions/core')

const { wrap, getDuration, update, mapMessage, getIndex } = require('../utils')

wrap(async () => {
  const dur = getDuration()
  await update(mapMessage(text => text.replace('running:', 'approved:') + dur))
  core.exportVariable('SLACK_STEP_INDEX', getIndex() + 1)
})
