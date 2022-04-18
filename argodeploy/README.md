# argodeploy

This action allows you to use a single action to deploy to either EKS or Kops clusters via argo.

## Required Environment Variables

| name | required | description |
|------|------|-------------|
| AWS_ACCESS_KEY_ID | If AWS_PROFILE not present | The access key id that will be used for AWS API calls |
| AWS_SECRET_ACCESS_KEY | If AWS_ACCESS_KEY_ID present | The secret access key that will be used for AWS API calls |
| AWS_PROFILE | If AWS_ACCESS_KEY_ID not present | If no access key provided, will instead attempt to use this profile for AWS API calls |
| SERVICE | Always | The name of the service as it is named within k8s. Ex: branding is `app-branding` |
| GITHUB_REPO | Always | The Org/Name of the github repo |
| GITHUB_USER | Always | The username associated with the token |
| GITHUB_TOKEN | Always | Token that can be used to access/alter the specified repo |

## Inputs

| Name | Required | Description |
|------|----------|-------------|
| eks | `true` | If true, will deploy to EKS |
| cluster_name | `true` | The name of the cluster we will deploy to |
| cluster_state | `false` | If eks=false, Location of kops statefile |
| security_group_id | `false` | The KOPS cluster SG that we will modify for API access |
| region | `true` | Region of k8s resources |
| namespace | `true` | Namespace where k8s resources reside |
| branch | `true` | Branch in the github repo that should be targeted |

## Outputs

None

## Example

```yaml
name: Deploy builder-api
on:
  push:
    branches:
      - main
    paths:
      - "packages/builder-api-node/**"

env:
  AWS_DEFAULT_REGION: us-west-2
  REGISTRY_ID: 667650582711
  REPOSITORY_BASE: 667650582711.dkr.ecr.us-west-2.amazonaws.com
  KUALIBUILD_NPM_TOKEN: ${{ secrets.KUALIBUILD_NPM_TOKEN }}
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  SERVICE: app-builder-api
  SERVICE_NAME: builder-api
  HONEYCOMB_KEY: ${{ secrets.HONEYCOMB_KEY }}
  SLACK_TOKEN: ${{ secrets.SLACK_TOKEN }}
  SLACK_CHANNEL: ${{ secrets.SLACK_CHANNEL }}
  GITHUB_TOKEN: ${{ secrets.GH_TOKEN }}
  GITHUB_USER: ${{ secrets.GH_USER }}
  GITHUB_REPO: kualibuild/builder-api-config

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v1
      - name: Set up Docker Buildx
        id: buildx
        uses: docker/setup-buildx-action@v1
      - uses: kualibuild/github-actions/slack-stream/create@master
        with:
          steps: "Build|Verify|Production US|Production CA|Tag Image"
      - name: Slack:Build
        uses: kualibuild/github-actions/slack-stream/start@master
      - uses: actions/setup-node@v1
        with:
          node-version: "14.x"
      - name: Set Version
        run: echo "VERSION=$(date +%Y%m%d%H%M%S)" >> "$GITHUB_ENV"
      - name: AWS Login
        run: |
          aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_BASE}
      - name: Building + Pushing Docker Image
        run: |
          export REPOSITORY=${REPOSITORY_BASE}/${SERVICE}
          export TAG="$(git rev-parse --short HEAD)"
          docker buildx build packages/builder-api-node/ \
            --build-arg KUALIBUILD_NPM_TOKEN=$KUALIBUILD_NPM_TOKEN \
            --platform linux/arm64,linux/amd64 \
            --cache-from type=registry,ref=${REPOSITORY}:latest \
            --tag ${REPOSITORY}:${TAG} \
            --tag ${REPOSITORY}:${VERSION} \
            --tag ${REPOSITORY}:latest \
            --push
      - uses: kualibuild/github-actions/slack-stream/finish@master
      - name: Prepping Slack_TS #TODO: This should be an action output rather than an artifact
        run: echo $SLACK_TS > .slack_ts
      - name: Upload Slack_TS
        uses: actions/upload-artifact@v1
        with:
          name: slack
          path: .slack_ts
      - if: ${{ failure() }}
        uses: kualibuild/github-actions/slack-stream/error@master
      - if: ${{ cancelled() }}
        uses: kualibuild/github-actions/slack-stream/cancel@master

  deploy_platform_verify:
    name: Deploy Verify
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: actions/checkout@v2
      - name: Deploy via ArgoCD
        uses: kualibuild/github-actions/argodeploy@master
        with:
          eks: "true"
          cluster_name: "eks-platform-verify"
          region: "us-east-2"
          namespace: "verify"
          branch: "verify"

  deploy_platform_prod:
    name: Deploy Prod
    runs-on: ubuntu-latest
    needs: deploy_platform_verify
    steps:
      - uses: actions/checkout@v2
      - name: Deploy via ArgoCD
        uses: kualibuild/github-actions/argodeploy@master
        with:
          eks: "false"
          cluster_name: "platform-prod.useast2.k8s.local"
          cluster_state: "s3://platform.useast2.k8s.local"
          security_group_id: "sg-0387614046a8d255e"
          region: "us-east-2"
          namespace: "prod"
          branch: "master"

  deploy_platform_prod_canada:
    name: Deploy Prod Canada
    runs-on: ubuntu-latest
    needs: deploy_platform_verify
    steps:
      - uses: actions/checkout@v2
      - name: Deploy via ArgoCD
        uses: kualibuild/github-actions/argodeploy@master
        with:
          eks: "false"
          cluster_name: "platform-prod.cacentral1.k8s.local"
          cluster_state: "s3://platform.cacentral1.k8s.local"
          security_group_id: "sg-0234fa91cd2170501"
          region: "ca-central-1"
          namespace: "prod"
          branch: "master"
```
