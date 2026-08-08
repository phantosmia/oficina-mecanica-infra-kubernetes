output "cluster_name" {
  description = "Nome final do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster EKS."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group principal do cluster EKS."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do provider OIDC do cluster EKS. Copie para o repositório oficina-mecanica-fiap (variável eks_oidc_provider_arn) para permitir a criação da IRSA role do service account da API."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "ID da VPC criada para o EKS."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC do EKS. Útil para preencher allowed_cidr_blocks no repositório oficina-mecanica-infra-banco-dados."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Subnets privadas usadas pelos nós do EKS."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Subnets públicas usadas pelos load balancers do cluster."
  value       = module.vpc.public_subnets
}

output "ecr_repository_name" {
  description = "Nome do repositório ECR da API."
  value       = aws_ecr_repository.api.name
}

output "ecr_repository_url" {
  description = "URL completa do repositório ECR da API. Copie para o repositório oficina-mecanica-fiap (variável ECR_REPOSITORY_URL)."
  value       = aws_ecr_repository.api.repository_url
}

output "configure_kubectl_command" {
  description = "Comando para atualizar o kubeconfig local para o cluster criado."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_login_command" {
  description = "Comando para autenticar o Docker no ECR."
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.api.repository_url)[0]}"
}

output "aws_load_balancer_controller_role_arn" {
  description = "Role IRSA para o service account do AWS Load Balancer Controller."
  value       = try(module.aws_load_balancer_controller_irsa[0].iam_role_arn, null)
}

output "github_actions_ecr_role_arn" {
  description = "Role IAM para GitHub Actions publicar a imagem no ECR via OIDC. Copie para o secret AWS_ROLE_TO_ASSUME do repositório oficina-mecanica-fiap."
  value       = try(aws_iam_role.github_actions_ecr[0].arn, null)
}

output "external_secrets_role_arn" {
  description = "Role IRSA usada pelo External Secrets Operator para ler Secrets Manager."
  value       = try(module.external_secrets_irsa[0].iam_role_arn, null)
}
