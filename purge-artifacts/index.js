const core = require('@actions/core')
const github = require('@actions/github')

const { owner, repo } = github.context.repo

async function * artifacts (octokit) {
  let hasMore = false
  let page = 1
  do {
    const args = { owner, repo, page, per_page: 100 }
    const { data } = await octokit.actions.listArtifactsForRepo(args)
    hasMore = data.total_count / 100 > page
    for (const artifact of data.artifacts) yield artifact
    page++
  } while (hasMore)
}

async function main () {
  try {
    const expires = +core.getInput('expires', { required: true })
    const token = core.getInput('token', { required: true })
    const octokit = github.getOctokit(token)
    let artifactCount = 0
    for await (const { id, created_at: createdAt } of artifacts(octokit)) {
      if (Date.now() - new Date(createdAt).getTime() < expires) return
      artifactCount++
      await octokit.actions.deleteArtifact({ owner, repo, artifact_id: id })
    }
    core.info(`Purged ${artifactCount} artifacts`)
  } catch (error) {
    core.setFailed(error.message)
  }
}

main()
