# NPM Publish Github Action

This github action will publish the project to an npm compatible registry if the
current version in your package.json is different than the one published.

# Usage

In your github actions workflow yaml file:

```yaml
jobs:
  your-publish-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1
      - uses: kualibuild/github-actions/npm-publish@master
        with:
          # Required
          npm_token: ${{ secrets.GITHUB_TOKEN }}
          # Not required, default shown
          npm_registry: https://npm.pkg.github.com
          # Not required, default shown
          package_path: '.'
```
