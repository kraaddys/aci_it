variable "aws_region" {
  description = "Регион AWS для развёртывания ресурсов"
  type        = string
  default     = "eu-central-1"
}

variable "env" {
  description = "Окружение (dev / stage / prod)"
  type        = string
  default     = "dev"
}
