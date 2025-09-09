<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_memory_store"></a> [memory\_store](#module\_memory\_store) | terraform-google-modules/memorystore/google | ~> 14.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authorized_network"></a> [authorized\_network](#input\_authorized\_network) | The name of the network where this network should be launched to | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the project where this VPC will be created | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where this Redis will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where to deploy resources | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_host"></a> [host](#output\_host) | Redis host |
| <a name="output_port"></a> [port](#output\_port) | Redis port |
<!-- END_TF_DOCS -->