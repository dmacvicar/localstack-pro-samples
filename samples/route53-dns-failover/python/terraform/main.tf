# Route53 DNS Failover - Terraform configuration
# Creates a hosted zone with health-checked failover routing

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    route53 = "http://localhost.localstack.cloud:4566"
  }
}

variable "zone_name" {
  default = "failover-tf.example.com"
}

# Hosted zone
resource "aws_route53_zone" "main" {
  name = var.zone_name
}

# Health check against LocalStack health endpoint
resource "aws_route53_health_check" "primary" {
  fqdn              = "localhost.localstack.cloud"
  port               = 4566
  resource_path      = "/_localstack/health"
  type               = "HTTP"
  request_interval   = 10
}

# Target 1: primary CNAME
resource "aws_route53_record" "target1" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "target1.${var.zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["primary.example.com"]
}

# Target 2: secondary CNAME
resource "aws_route53_record" "target2" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "target2.${var.zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["secondary.example.com"]
}

# Failover primary record
resource "aws_route53_record" "failover_primary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "app.${var.zone_name}"
  type           = "CNAME"
  set_identifier = "primary"

  alias {
    name                   = aws_route53_record.target1.name
    zone_id                = aws_route53_zone.main.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

# Failover secondary record
resource "aws_route53_record" "failover_secondary" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = "app.${var.zone_name}"
  type           = "CNAME"
  set_identifier = "secondary"

  alias {
    name                   = aws_route53_record.target2.name
    zone_id                = aws_route53_zone.main.zone_id
    evaluate_target_health = true
  }

  failover_routing_policy {
    type = "SECONDARY"
  }
}

# Outputs
output "hosted_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "hosted_zone_name" {
  value = var.zone_name
}

output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "failover_record" {
  value = "app.${var.zone_name}"
}

output "target1_record" {
  value = "target1.${var.zone_name}"
}

output "target2_record" {
  value = "target2.${var.zone_name}"
}
