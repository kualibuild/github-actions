const core = require('@actions/core')
const github = require('@actions/github')

const { owner, repo } = github.context.repo

async function getLastPage (octokit) {
  const args = { owner, repo, page: 1, per_page: 1 }
  const res = await octokit.actions.listArtifactsForRepo(args)
  core.info(`Total Artifact Count: ${res.data.total_count}`)
  return Math.ceil(res.data.total_count / 100)
}

const ms = a => new Date(a.created_at).getTime()

async function purge (octokit, expires, page) {
  if (page <= 0) return 0
  const args = { owner, repo, page, per_page: 100 }
  const res = await octokit.actions.listArtifactsForRepo(args)
  const expired = res.data.artifacts.filter(a => ms(a) < expires)
  for (const { id } of expired) {
    await octokit.actions.deleteArtifact({ owner, repo, artifact_id: id })
  }
  return expired.length + (await purge(octokit, expires, page - 1))
}

async function run () {
  try {
    const expires = +core.getInput('expires', { required: true })
    const token = core.getInput('token', { required: true })
    const octokit = github.getOctokit(token)
    const lastPage = await getLastPage(octokit)
    const purgeCount = await purge(octokit, Date.now() - expires, lastPage)
    core.info(`Purged Artifacts: ${purgeCount}`)
  } catch (error) {
    core.setFailed(error.message)
  }
}

run()
