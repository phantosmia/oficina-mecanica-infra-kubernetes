variable "project_name" {
  description = "Nome lógico do projeto para tags e nomes de recursos."
  type        = string
  default     = "oficina-mecanica-fiap"
}

variable "environment" {
  description = "Identificador do ambiente AWS."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Região AWS onde os recursos serão provisionados."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS. Se vazio, usa <project_name>-<environment>."
  type        = string
  default     = ""
}

variable "eks_admin_principal_arn" {
  description = "ARN IAM que receberá acesso administrativo ao EKS. Útil no AWS Academy, onde iam:GetRole da role voclabs pode ser bloqueado."
  type        = string
  default     = ""
}

variable "eks_cluster_role_arn" {
  description = "ARN de uma IAM role existente para o control plane do EKS. Use em labs que bloqueiam iam:CreateRole."
  type        = string
  default     = ""
}

variable "eks_node_role_arn" {
  description = "ARN de uma IAM role existente para o node group do EKS. Use em labs que bloqueiam iam:CreateRole."
  type        = string
  default     = ""
}

variable "enable_irsa_resources" {
  description = "Cria recursos IAM/OIDC/IRSA para controllers e secrets. Desabilite em AWS Academy Labs com IAM restrito."
  type        = bool
  default     = true
}

variable "enable_github_actions_oidc" {
  description = "Cria OIDC provider e role para GitHub Actions publicar no ECR. Desabilite em AWS Academy Labs com IAM restrito."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes no EKS. 1.30 saiu de suporte padrão da AWS — confira as versões com AMI otimizada disponível (`aws ssm get-parameter --name /aws/service/eks/optimized-ami/<versao>/amazon-linux-2023/x86_64/standard/recommended/image_id`) se o apply falhar."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do cluster. Mantenha fora do range usado pela VPC do banco de dados (repositório oficina-mecanica-infra-banco-dados) para permitir VPC Peering."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 para os nós gerenciados do EKS."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós do node group padrão."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nós do node group padrão."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nós do node group padrão."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Tamanho do disco dos nós gerenciados do EKS, em GiB."
  type        = number
  default     = 30
}

variable "ecr_repository_name" {
  description = "Nome do repositório ECR que armazenará a imagem da API do repositório oficina-mecanica-fiap."
  type        = string
  default     = "oficina-mecanica-fiap"
}

variable "ecr_force_delete" {
  description = "Remove imagens do ECR ao destruir o repositório."
  type        = bool
  default     = false
}

variable "tf_state_bucket" {
  description = "Bucket S3 do backend remoto do Terraform (o mesmo criado por infra/backend no repositório oficina-mecanica-fiap), usado para ler via terraform_remote_state o output rds_secret_arn do repositório oficina-mecanica-infra-banco-dados."
  type        = string
  default     = "oficina-mecanica-fiap-terraform-state"
}

variable "tf_state_region" {
  description = "Região do backend S3 do state remoto."
  type        = string
  default     = "us-east-1"
}

variable "database_state_key" {
  description = "Key do state do repositório oficina-mecanica-infra-banco-dados no backend S3 compartilhado. Ajuste para o ambiente real (ex.: database/homologacao/terraform.tfstate) ao aplicar em homologacao/producao."
  type        = string
  default     = "database/dev/terraform.tfstate"
}

variable "github_repository" {
  description = "Repositório GitHub autorizado a publicar imagens no ECR via OIDC, no formato owner/repo. É o repositório da aplicação principal (oficina-mecanica-fiap), não este."
  type        = string
  default     = "phantosmia/oficina-mecanica-fiap"
}

variable "github_branch" {
  description = "Branch autorizada a publicar imagens no ECR via OIDC."
  type        = string
  default     = "main"
}

variable "install_aws_load_balancer_controller" {
  description = "Instala o AWS Load Balancer Controller no EKS via Helm."
  type        = bool
  default     = true
}

variable "aws_load_balancer_controller_chart_version" {
  description = "Versão do chart Helm do AWS Load Balancer Controller."
  type        = string
  default     = "1.8.1"
}

variable "install_external_secrets_operator" {
  description = "Instala o External Secrets Operator no EKS via Helm."
  type        = bool
  default     = true
}

variable "external_secrets_chart_version" {
  description = "Versão do chart Helm do External Secrets Operator."
  type        = string
  default     = "0.10.5"
}

variable "install_metrics_server" {
  description = "Instala o metrics-server no EKS via Helm para habilitar HPA por CPU/memória."
  type        = bool
  default     = true
}

variable "metrics_server_chart_version" {
  description = "Versão do chart Helm do metrics-server."
  type        = string
  default     = "3.12.1"
}

variable "install_new_relic_integration" {
  description = "Instala a New Relic Kubernetes integration (nri-bundle) no EKS via Helm — cobertura de infraestrutura do cluster (ADR-0007). Só instala de fato se new_relic_license_key também estiver preenchida."
  type        = bool
  default     = true
}

variable "new_relic_bundle_chart_version" {
  description = "Versão do chart Helm nri-bundle (New Relic Kubernetes integration)."
  type        = string
  default     = "8.0.18"
}

variable "new_relic_license_key" {
  description = "License key (ingest) do New Relic (ADR-0007). Vazia (padrão) não instala a integração, mesmo com install_new_relic_integration=true — evita um DaemonSet órfão sem credencial válida."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  description = "Tags adicionais aplicadas aos recursos AWS."
  type        = map(string)
  default     = {}
}
