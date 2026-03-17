resource "aws_acm_certificate" "app" {
  domain_name       = "app.thirdlf03.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn = aws_acm_certificate.app.arn
  # DNS validation records must be added manually in Cloudflare DNS.
  # After adding the CNAME records, this resource will wait for validation.
}
