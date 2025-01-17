data "aws_caller_identity" "current" {}

locals {
  name   = "unicorn-ui"
  region = var.region

  container_port = 7007 # Container port is specific to this app example
  container_name = "unicorn-ui"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/${var.repository_owner}/ecs-blueprints"
  }
}

################################################################################
# ECS Blueprint
################################################################################

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.6"

  name          = local.name
  desired_count = 3
  cluster_arn   = data.aws_ecs_cluster.core_infra.arn

  # Task Definition
  enable_execute_command = true
  task_exec_secret_arns = [
    data.aws_secretsmanager_secret.github_token.arn,
    data.aws_secretsmanager_secret.postgresdb_master_password.arn,
  ]

  container_definitions = {
    (local.container_name) = {
      image                    = "${module.ecr.repository_url}:${var.image_tag}"
      readonly_root_filesystem = false

      environment = [
        { name = "BASE_URL", value = "http://${module.alb.dns_name}" },
        # { name = "POSTGRES_HOST", value = module.db.db_instance_endpoint },
        { name = "POSTGRES_HOST", value = "10.0.10.139" },
        { name = "POSTGRES_PORT", value = "5432" },
        { name = "POSTGRES_USER", value = "postgres" },
      ]

      secrets = [
        { name = "GITHUB_TOKEN", valueFrom = data.aws_secretsmanager_secret.github_token.arn },
        { name = "POSTGRES_PASSWORD", valueFrom = data.aws_secretsmanager_secret.postgresdb_master_password.arn }
      ]

      port_mappings = [
        {
          protocol      = "tcp",
          containerPort = local.container_port
        }
      ]
    }
  }

  service_registries = {
    registry_arn = aws_service_discovery_service.this.arn
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ecs-task"].arn
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = data.aws_subnets.private.ids
  security_group_rules = {
    ingress_alb_service = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}

resource "aws_service_discovery_service" "this" {
  name = local.name

  dns_config {
    namespace_id = data.aws_service_discovery_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  # For example only
  enable_deletion_protection = false

  vpc_id  = data.aws_vpc.vpc.id
  subnets = data.aws_subnets.public.ids
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_https = {
      from_port   = 443
      to_port     = 445
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = { for subnet in data.aws_subnet.private_cidr :
    (subnet.availability_zone) => {
      ip_protocol = "-1"
      cidr_ipv4   = subnet.cidr_block
    }
  }

  listeners = {
    http = {
      port     = "80"
      protocol = "HTTP"
      redirect = {
        port = 443
        protocol = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    https = {
      port                        = 443
      protocol                    = "HTTPS"
      ssl_policy                  = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
      certificate_arn             = data.aws_acm_certificate.wildcard.arn

      action_type     = "authenticate-oidc"
      authenticate_oidc = {
        authentication_request_extra_params = {
          display = "page"
          prompt  = "login"
        }
        authorization_endpoint = var.auth_oidc.authorization_endpoint
        client_id              = var.auth_oidc.client_id
        client_secret          = var.auth_oidc.client_secret
        issuer                 = var.auth_oidc.issuer
        token_endpoint         = var.auth_oidc.token_endpoint
        user_info_endpoint     = var.auth_oidc.user_info_endpoint
        session_cookie_name = "backstage"
        session_timeout = 3600
        scope = "openid email offline_access"
      }

      forward = {
        target_group_key = "ecs-task"
      }
    }

  }

  target_groups = {
    ecs-task = {
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }
  }

  tags = local.tags
}

resource "aws_route53_record" "backstage" {
  zone_id = data.aws_route53_zone.poc.zone_id
  name    = "izlite-backstage.${var.domain_name}"
  type    = "CNAME"
  ttl     = "300"
  records = [module.alb.dns_name]
}

# module "db" {
#   source  = "terraform-aws-modules/rds/aws"
#   version = "6.3.0"

#   identifier = "${local.name}-db2"

#   # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
#   engine               = "postgres"
#   engine_version       = "14"
#   family               = "postgres14" # DB parameter group
#   major_engine_version = "14"         # DB option group
#   instance_class       = "db.t4g.medium"

#   allocated_storage     = 10
#   max_allocated_storage = 20

#   # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
#   # "Error creating DB Instance: InvalidParameterValue: MasterUsername
#   # user cannot be used as it is a reserved word used by the engine"
#   username = "postgres"
#   manage_master_user_password = false
#   password = data.aws_secretsmanager_secret_version.postgresdb_master_password.secret_string
#   port     = 5432

#   db_subnet_group_name   = "backstage-db"
#   vpc_security_group_ids = ["sg-0d6a0b766f68daed7"]

#   maintenance_window              = "Mon:00:00-Mon:03:00"
#   backup_window                   = "03:00-06:00"
#   # enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
#   # create_cloudwatch_log_group     = true

#   backup_retention_period = 1
#   skip_final_snapshot     = true
#   deletion_protection     = false


#   parameters = [
#     {
#       name  = "autovacuum"
#       value = 1
#     },
#     {
#       name  = "client_encoding"
#       value = "utf8"
#     }
#   ]

#   tags = local.tags
# }

################################################################################
# RDS Aurora for Backstage backend db
################################################################################

module "aurora_postgresdb" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name   = "backstage-db"
  engine = "aurora-postgresql"
  # engine_mode            = "serverless"
  create_db_subnet_group = true
  serverlessv2_scaling_configuration = {
    max_capacity = 2.0
    min_capacity = 1.0
  }

  vpc_id  = data.aws_vpc.vpc.id
  subnets = data.aws_subnets.private.ids
  security_group_rules = {
    private_subnets_ingress = {
      description = "Allow ingress from VPC private subnets"
      cidr_blocks = [for s in data.aws_subnet.private_cidr : s.cidr_block]
    }
  }

  storage_encrypted   = true
  apply_immediately   = true
  monitoring_interval = 60

  scaling_configuration = {
    min_capacity = 2
    max_capacity = 2
  }

  master_username = "postgres"
  master_password = data.aws_secretsmanager_secret_version.postgresdb_master_password.secret_string
  port            = 5432

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

resource "random_id" "this" {
  byte_length = "2"
}

data "aws_secretsmanager_secret" "postgresdb_master_password" {
  name = var.postgresdb_master_password
}

data "aws_secretsmanager_secret_version" "postgresdb_master_password" {
  secret_id = data.aws_secretsmanager_secret.postgresdb_master_password.id
}

data "aws_secretsmanager_secret" "github_token" {
  name = var.github_token_secret_name
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = data.aws_secretsmanager_secret.github_token.id
}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["core-infra"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["core-infra-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["core-infra-private-*"]
  }
}

data "aws_subnet" "private_cidr" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

data "aws_ecs_cluster" "core_infra" {
  cluster_name = "core-infra"
}

data "aws_service_discovery_dns_namespace" "this" {
  name = "default.${data.aws_ecs_cluster.core_infra.cluster_name}.local"
  type = "DNS_PRIVATE"
}



