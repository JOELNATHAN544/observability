# Project Module

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gis"></a> [gis](#module\_gis) | terraform-google-modules/project-factory/google | ~> 18.0 |
| <a name="module_mighty_role"></a> [mighty\_role](#module\_mighty\_role) | terraform-google-modules/iam/google//modules/custom_role_iam | ~> 8.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_enabled_services"></a> [api\_enabled\_services](#input\_api\_enabled\_services) | The list of apis necessary for the project | `list(string)` | `[]` | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account assign to project | `string` | n/a | yes |
| <a name="input_credentials"></a> [credentials](#input\_credentials) | n/a | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | Folder ID | `string` | `null` | no |
| <a name="input_iam_principals"></a> [iam\_principals](#input\_iam\_principals) | List of role (key) names to grant permissions to | `list(string)` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Map of labels for project | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Project Name | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Project Name | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Unique project ID | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | Project region | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | n/a |
<!-- END_TF_DOCS -->