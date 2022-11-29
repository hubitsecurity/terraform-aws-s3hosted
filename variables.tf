variable "aws_region" {
  type        = string
  description = "The AWS region to put the bucket into"
  default     = "us-east-1"
}

variable "site_domain" {
  type        = string
  description = "The domain name to use for the static site"
}

variable "subdomain" {
  type        = string
  description = "Subdomain where the S3 will held the content and cloudflare will point to"
}

variable "environment" {
  type        = string
  description = "should attend to one of prd, dev, hml"
  validation {
    condition     = try(length(regex("(prd|dev|hml)", var.environment)) == 1, false)
    error_message = "Try one valid value."
  }
}

variable "path_to_deploy_files" {
  type        = string
  description = "Absolute path for files"
  validation {
    condition     = try(length(regex("(^/.*)", var.path_to_deploy_files)) == 1, false)
    error_message = "Path should be absolute."
  }
}