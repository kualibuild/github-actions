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