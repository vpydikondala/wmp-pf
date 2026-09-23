variable "aws_region" { type = string default = "eu-west-2" }
variable "environment" { type = string validation { condition = contains(["dev","uat","prod"], var.environment) error_message = "environment must be dev, uat or prod." } }
variable "project_name" { type = string default = "occupancy-platform" }
variable "infra_state_bucket" { type = string default = "wmp-tfstate" }
variable "infra_state_kms_key_arn" { type = string }
variable "container_image_tag" { type = string }
variable "inbound_port" { type = number default = 8080 }
variable "management_port" { type = number default = 8090 }
variable "ecs_cpu" { type = number default = 512 }
variable "ecs_memory" { type = number default = 1024 }
variable "desired_count" {
  type = map(number)
  default = { inbound = 1, processor = 1, management = 1 }
}
variable "dashboard_sync_schedule" { type = string default = "rate(5 minutes)" }
