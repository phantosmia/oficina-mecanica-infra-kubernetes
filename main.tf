terraform {
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.aws_region
}

# TODO: migrar aqui o Terraform de VPC/EKS/ECR/IRSA hoje em infra/aws do oficina-mecanica-fiap
