# SSL Certificates Configuration for Multiple Domains
# This module creates ACM certificates and Route53 validation records
# Integrates with AEIMS multi-site architecture and nginx SNI configuration

# Data sources for existing Route53 hosted zones
data "aws_route53_zone" "nycflirts" {
  count        = contains(keys(var.additional_domains), "nycflirts") ? 1 : 0
  name         = "nycflirts.com"
  private_zone = false
}

data "aws_route53_zone" "flirtsnyc" {
  count        = contains(keys(var.additional_domains), "flirtsnyc") ? 1 : 0
  name         = "flirts.nyc"
  private_zone = false
}

# ACM Certificates for additional domains
resource "aws_acm_certificate" "domain_certificates" {
  for_each = var.additional_domains

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.sans
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-${each.key}-cert-${var.environment}"
    Domain      = each.value.domain_name
    Environment = var.environment
  }
}

# Route53 validation records for ACM certificates
resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in flatten([
      for domain_key, cert in aws_acm_certificate.domain_certificates : [
        for dvo in cert.domain_validation_options : {
          domain_key   = domain_key
          domain_name  = dvo.domain_name
          record_name  = dvo.resource_record_name
          record_type  = dvo.resource_record_type
          record_value = dvo.resource_record_value
        }
      ]
    ]) : "${dvo.domain_key}-${dvo.domain_name}" => dvo
    # Only include records for domains with hosted zones
    if (
      dvo.domain_key == "nycflirts" && length(data.aws_route53_zone.nycflirts) > 0
    ) || (
      dvo.domain_key == "flirtsnyc" && length(data.aws_route53_zone.flirtsnyc) > 0
    )
  }

  allow_overwrite = true
  name            = each.value.record_name
  records         = [each.value.record_value]
  ttl             = 60
  type            = each.value.record_type
  zone_id = each.value.domain_key == "nycflirts" ? (
    data.aws_route53_zone.nycflirts[0].zone_id
  ) : each.value.domain_key == "flirtsnyc" ? (
    data.aws_route53_zone.flirtsnyc[0].zone_id
  ) : null
}

# ACM certificate validation
resource "aws_acm_certificate_validation" "domain_validations" {
  for_each = {
    for domain_key, domain_config in var.additional_domains : domain_key => domain_config
    if (
      domain_key == "nycflirts" && length(data.aws_route53_zone.nycflirts) > 0
    ) || (
      domain_key == "flirtsnyc" && length(data.aws_route53_zone.flirtsnyc) > 0
    )
  }

  certificate_arn         = aws_acm_certificate.domain_certificates[each.key].arn
  validation_record_fqdns = [
    for record_key, record in aws_route53_record.certificate_validation :
    record.fqdn
    if startswith(record_key, "${each.key}-")
  ]

  timeouts {
    create = "10m"
  }

  depends_on = [aws_route53_record.certificate_validation]
}

# Create Route53 records for domain routing (optional - if you want to point domains to ALB)
resource "aws_route53_record" "domain_alb_records" {
  for_each = {
    for domain_key, domain_config in var.additional_domains : domain_key => domain_config
    if domain_key == "nycflirts" ? length(data.aws_route53_zone.nycflirts) > 0 : (
      domain_key == "flirtsnyc" ? length(data.aws_route53_zone.flirtsnyc) > 0 : false
    )
  }

  zone_id = each.key == "nycflirts" ? (
    length(data.aws_route53_zone.nycflirts) > 0 ? data.aws_route53_zone.nycflirts[0].zone_id : null
  ) : each.key == "flirtsnyc" ? (
    length(data.aws_route53_zone.flirtsnyc) > 0 ? data.aws_route53_zone.flirtsnyc[0].zone_id : null
  ) : null

  name = each.value.domain_name
  type = "A"

  alias {
    name                   = aws_lb.aeims_alb.dns_name
    zone_id                = aws_lb.aeims_alb.zone_id
    evaluate_target_health = true
  }
}

# Create www subdomain records
resource "aws_route53_record" "www_domain_alb_records" {
  for_each = {
    for domain_key, domain_config in var.additional_domains : domain_key => domain_config
    if length(domain_config.sans) > 0 && domain_key == "nycflirts" ? length(data.aws_route53_zone.nycflirts) > 0 : (
      domain_key == "flirtsnyc" ? length(data.aws_route53_zone.flirtsnyc) > 0 : false
    )
  }

  zone_id = each.key == "nycflirts" ? (
    length(data.aws_route53_zone.nycflirts) > 0 ? data.aws_route53_zone.nycflirts[0].zone_id : null
  ) : each.key == "flirtsnyc" ? (
    length(data.aws_route53_zone.flirtsnyc) > 0 ? data.aws_route53_zone.flirtsnyc[0].zone_id : null
  ) : null

  name = length(each.value.sans) > 0 ? each.value.sans[0] : null
  type = "A"

  alias {
    name                   = aws_lb.aeims_alb.dns_name
    zone_id                = aws_lb.aeims_alb.zone_id
    evaluate_target_health = true
  }
}

# Output the certificate ARNs
output "additional_certificate_arns" {
  description = "ARNs of additional domain certificates"
  value = {
    for k, v in aws_acm_certificate_validation.domain_validations : k => v.certificate_arn
  }
}

output "additional_domain_names" {
  description = "Domain names configured with certificates"
  value = {
    for k, v in var.additional_domains : k => {
      domain_name = v.domain_name
      sans        = v.sans
    }
  }
}