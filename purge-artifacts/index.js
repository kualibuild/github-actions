const core = require('@actions/core')
const github = require('@actions/github')

const { owner, repo } = github.context.repo

async function fetchArtifacts (octokit) {
  const args = { owner, repo, page: 1, per_page: 100 }
  const res = await octokit.actions.listArtifactsForRepo(args)
  core.info(`total artifacts: ${res.data.total_count}`)
  core.info(JSON.stringify(res.data.artifacts[0], null, 2))
  return res.data.artifacts
}

async function purge (octokit, expires) {
  let purgeCount = 0
  const artifacts = await fetchArtifacts(octokit)
  if (!artifacts.length) return 0
  for (const artifact of artifacts) {
    const { id, created_at: createdAt } = artifact
    if (Date.now() - new Date(createdAt).getTime() < expires) return
    purgeCount++
    await octokit.actions.deleteArtifact({ owner, repo, artifact_id: id })
  }
  return purgeCount + purge(octokit, expires)
}

async function run () {
  try {
    const expires = +core.getInput('expires', { required: true })
    const token = core.getInput('token', { required: true })
    const octokit = github.getOctokit(token)
    const purgeCount = await purge(octokit, expires)
    core.info(`Purged ${purgeCount} artifacts`)
  } catch (error) {
    core.info('failed')
    core.setFailed(error.message)
  }
}

run()
