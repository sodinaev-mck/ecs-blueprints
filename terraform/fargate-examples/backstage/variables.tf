variable "repository_owner" {
  description = "The name of the owner of the Github repository"
  type        = string
}

variable "repository_name" {
  description = "The name of the Github repository"
  type        = string
}

variable "repository_branch" {
  description = "The name of branch the Github repository, which is going to trigger a new CodePipeline excecution"
  type        = string
  default     = "main"
}

variable "github_token_secret_name" {
  description = "Name of secret manager secret storing github token for auth"
  type        = string
}

variable "postgresdb_master_password" {
  description = "AWS secrets manager secret name that stores the db master password"
  type        = string
  sensitive   = true
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "image_tag" {
  description = "ECR image tag" # had to specify after latest tag vanished somehow.
  type = string
}

variable "domain_name" {
  description = "Domain name to use for wildcard cert"
  type = string
}

variable "auth_oidc" {
  type = object({
    issuer = string
    authorization_endpoint = string
    token_endpoint = string
    user_info_endpoint = string
    client_id = string
    client_secret = string
  })
}
