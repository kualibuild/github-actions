# Docker Publish Github Action

This github action will publish to a docker compatible registry.

# Usage

In your github actions workflow yaml file:

```yaml
jobs:
  your-publish-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1
      - uses: kualibuild/github-actions/docker-publish@master
        with:
          # Not Required, default shown
          docker_password: ${{ github.token }}
          # Not required, default shown
          docker_username: ${{ github.actor }}
          # Not required, default shown
          docker_image_name: this_defaults_to_the_repo_name
          # Not required, default shown
          docker_registry: docker.pkg.github.com
          # Not required, default shown
          docker_context_path: '.'
          # Not required, default shown
          dockerfile: 'Dockerfile'
          # Not required, default shown, passed into `docker build`
          build_params: ''
```
