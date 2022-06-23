const { execSync } = require('child_process')

const PATH = `https://omnibus-aptible-toolbelt.s3.amazonaws.com/aptible/omnibus-aptible-toolbelt/master/340/pkg`
const NAME = `aptible-toolbelt_0.19.3+20220317192554~debian.9.13-1_amd64.deb`

const APP_NAME = (process.env.INPUT_APP_NAME || '').trim()
if (!APP_NAME) throw new Error('app_name is required')

const APTIBLE_USERNAME = (process.env.INPUT_APTIBLE_USERNAME || '').trim()
if (!APTIBLE_USERNAME) throw new Error('aptible_username is required')

const APTIBLE_PASSWORD = (process.env.INPUT_APTIBLE_PASSWORD || '').trim()
if (!APTIBLE_PASSWORD) throw new Error('aptible_password is required')

const raw = execSync(
  `ruby -rjson -ryaml -e "puts YAML.load_file('.github/workflows/deploy-env.yaml').to_json"`,
  'utf-8'
)
const { env } = JSON.parse(raw).jobs['deploy-env'].steps[1]

const environments = [
  // { prefix: 'US', obj: {} },
  // { prefix: 'CA', obj: {} },
  { prefix: 'VERIFY', env: 'platform-verify', obj: {} }
]

const prefixes = environments.map(a => a.prefix)

for (let key in env) {
  if (key.includes(':')) key = key.split(':').at(-1)
  for (const e of environments) {
    e.obj[key] = process.env[`${e.prefix}:${key}`] || process.env[key]
  }
}

execSync(`wget ${PATH}/${encodeURIComponent(NAME)}`)
execSync(`sudo dpkg -i ${NAME}`)
execSync(
  `aptible login --email "${APTIBLE_USERNAME}" --password "${APTIBLE_PASSWORD}"`
)

for (const e of environments) {
  const cmd = [
    'aptible',
    'config:set',
    `--app ${APP_NAME}`,
    `--environment ${e.env}`,
    ...Object.keys(e.obj).map(key => `${key}=${e.obj[key]}`)
  ].join(' ')

  execSync(cmd)
}
