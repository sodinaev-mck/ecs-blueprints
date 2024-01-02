variable "app_name" {
  type = string
  description = "ECS Cluster name. Prefer a single alphanum word. Don't bother with elaborate combos. Single word will do. Seriously."
}

variable "region" {
    type = string
    description = "AWS region name."
    default = "us-east-1"
}

variable "domain_name" {

}