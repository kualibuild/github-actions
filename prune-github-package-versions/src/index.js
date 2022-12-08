import * as core from '@actions/core'
import { context, getOctokit } from '@actions/github'

async function run () {
  try {
    const owner = core.getInput('owner') || context.repo.owner
    const packageName = core.getInput('package-name') || context.repo.repo
    const packageType = core.getInput('package-type')
    const token = core.getInput('token', { required: true })
    const user = core.getInput('user')
    const minVersionsToKeep = Number.parseInt(
      core.getInput('min-versions-to-keep'),
      10
    )
    if (minVersionsToKeep < 0) {
      core.info('not deleting anything')
      return
    }
    if (!isPackageType(packageType)) {
      throw new Error(`${packageType} is not a valid package type`)
    }
    const octokit = createOctokit(token)
    const versions = await asyncIteratorToArray(
      getVersions({ owner, packageName, packageType, octokit })
    )
    const toDelete = versions.slice(minVersionsToKeep)
    for (const packageVersion of toDelete) {
      if (user === 'true') {
        await octokit.rest.packages.deletePackageVersionForUser({
          username: owner,
          package_name: packageName,
          package_version_id: packageVersion.id,
          package_type: packageType
        })
      } else {
        await octokit.rest.packages.deletePackageVersionForOrg({
          org: owner,
          package_name: packageName,
          package_version_id: packageVersion.id,
          package_type: packageType
        })
      }
    }
    core.notice(`Deleted count: ${toDelete.length}`)
  } catch (error) {
    if (error instanceof Error) core.setFailed(error.message)
  }
}

/** @typedef {ReturnType<createOctokit>} Octokit */
/** @typedef {'npm'|'maven'|'rubygems'|'docker'|'nuget'|'container'} PackageType */

/**
 * @param {string} token
 */
function createOctokit (token) {
  return getOctokit(token)
}

/** @type {Set<PackageType>} */
const PACKAGE_TYPES = new Set([
  'npm',
  'maven',
  'rubygems',
  'docker',
  'nuget',
  'container'
])

/**
 * @param {string} value
 * @returns {value is PackageType}
 */
function isPackageType (value) {
  // @ts-ignore
  return PACKAGE_TYPES.has(value)
}

/**
 * @param {object} params
 * @param {string} params.owner
 * @param {string} params.packageName
 * @param {PackageType} params.packageType
 * @param {Octokit} params.octokit
 */
async function* getVersions ({ owner, packageName, packageType, octokit }) {
  const perPage = 100
  let keepPaging = true
  let page = 1
  do {
    const response =
      await octokit.rest.packages.getAllPackageVersionsForPackageOwnedByOrg({
        org: owner,
        package_name: packageName,
        package_type: packageType,
        per_page: perPage,
        page
      })
    for (const version of response.data) yield version
    if (response.data.length < perPage) keepPaging = false
    else page += 1
  } while (keepPaging)
}

/**
 * @template T
 * @param {AsyncGenerator<T>} iterator
 * @returns {Promise<T[]>}
 */
async function asyncIteratorToArray (iterator) {
  const results = []
  for await (const value of iterator) results.push(value)
  return results
}

run()
