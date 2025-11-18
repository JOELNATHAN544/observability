region           = "europe-west3"
name             = "observe"
root_domain_name = "observe.camer.digital"
environment      = "prod"

project_id = "observe-472521"

wazuh_helm_chart_version = "0.6.1-rc.1"

subject = {
  country = "CM"
  locality = "Bangangte"
  organization = "adorsys GIS"
  common_name = "root-ca"
}
