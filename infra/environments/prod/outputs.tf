output "site_url" {
  description = "The live site"
  value       = one(module.bluegreen[*].alb_dns_name) == null ? null : "http://${one(module.bluegreen[*].alb_dns_name)}"
}

output "service_name" {
  value = one(module.app[*].service_name)
}

output "codedeploy_app_name" {
  value = one(module.bluegreen[*].codedeploy_app_name)
}

output "codedeploy_deployment_group_name" {
  value = one(module.bluegreen[*].codedeploy_deployment_group_name)
}
