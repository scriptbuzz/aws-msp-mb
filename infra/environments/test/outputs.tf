output "service_name" {
  value = one(module.app[*].service_name)
}

output "task_definition_family" {
  value = one(module.app[*].task_definition_family)
}
