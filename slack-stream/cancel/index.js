const { wrap, getDuration, update, mapMessage } = require('../utils')

wrap(async () => {
  const duration = getDuration()
  await update(fullText =>
    mapMessage(text => {
      if (text.indexOf('running:') === -1) return text
      return text.replace('running:', 'cancelled:') + duration
    })(fullText)
      .replace(/pending:/g, 'cancelled:')
      .replace(/running:/g, 'cancelled:')
  )
})
