data "aws_acm_certificate" "wildcard" {
  domain   = "*.${var.domain_name}"
  statuses = ["ISSUED"]
}

data "aws_route53_zone" "poc" {
  name = var.domain_name
}