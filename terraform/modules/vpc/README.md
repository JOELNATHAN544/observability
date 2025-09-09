# VPC Module

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_private-service-access"></a> [private-service-access](#module\_private-service-access) | terraform-google-modules/sql-db/google//modules/private_service_access | ~> 25.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-google-modules/network/google | ~> 10.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_labels"></a> [labels](#input\_labels) | Map of labels for project | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the project where this VPC will be created | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where this VPC will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where to deploy resources | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | The CIDR block for the VPC | `string` | `"43.21.0.0/17"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | n/a |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | n/a |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | n/a |
| <a name="output_sub_network_names"></a> [sub\_network\_names](#output\_sub\_network\_names) | n/a |
<!-- END_TF_DOCS -->