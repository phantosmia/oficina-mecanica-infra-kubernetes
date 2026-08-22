data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Le o state remoto do repositorio oficina-mecanica-infra-banco-dados (mesmo
# backend S3 compartilhado, key diferente) para obter o ARN do secret do RDS
# automaticamente, sem exigir uma variavel copiada manualmente a cada apply.
data "terraform_remote_state" "database" {
  backend = "s3"

  config = {
    bucket = var.tf_state_bucket
    key    = var.database_state_key
    region = var.tf_state_region
  }
}

locals {
  cluster_name   = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"
  azs            = slice(data.aws_availability_zones.available.names, 0, 3)
  rds_secret_arn = try(data.terraform_remote_state.database.outputs.rds_secret_arn, "")

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "FIAP"
      Component   = "kubernetes"
    },
    var.tags,
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  tags = local.common_tags
}

# --- VPC Peering com a VPC do banco de dados ------------------------------
# A aplicação principal (rodando nos nodes desta VPC) precisa alcançar o RDS
# PostgreSQL, que fica numa VPC própria e isolada (oficina-mecanica-infra-
# banco-dados, sem Internet Gateway/NAT, ver ADR-0005 em oficina-mecanica-
# fiap). As duas VPCs não têm CIDR sobreposto de propósito (10.0.0.0/16
# aqui, 10.90.0.0/24 lá) justamente para permitir este peering.
#
# Vive neste repositório (não no do banco) porque a ordem de apply da
# Fase 3 já garante que o state do banco existe antes deste repositório
# (data.terraform_remote_state.database acima) — o inverso não seria
# verdade, e o banco de dados apply primeiro, sozinho, sem saber que o EKS
# vai existir. Por isso a rota "de volta" (aws_route.database_to_private
# abaixo) também é gerenciada por aqui, mirando a route table default da
# VPC do banco via os outputs vpc_cidr_block/default_route_table_id
# daquele repositório — mesma conta/região, então uma aws_route resource
# consegue apontar pra lá sem problema, mesmo não sendo "dono" daquele
# state.
#
# O security group do RDS (allowed_cidr_blocks, no repositório do banco)
# continua exigindo liberação manual do CIDR desta VPC — o peering só
# resolve o roteamento, não a autorização.
resource "aws_vpc_peering_connection" "eks_to_database" {
  vpc_id      = module.vpc.vpc_id
  peer_vpc_id = data.terraform_remote_state.database.outputs.vpc_id
  auto_accept = true # mesma conta e região: dispensa um accepter separado

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-to-database" })
}

resource "aws_route" "private_to_database" {
  # for_each com toset(module.vpc.private_route_table_ids) falha aqui: os IDs
  # das route tables só existem depois do apply (não dá pra usar valores
  # desconhecidos como chave de for_each). O tamanho da lista, porém, já é
  # conhecido em tempo de plan (com single_nat_gateway=true o módulo cria
  # uma única route table privada compartilhada, não uma por AZ), então
  # count + indexação funciona.
  count = length(module.vpc.private_route_table_ids)

  route_table_id            = module.vpc.private_route_table_ids[count.index]
  destination_cidr_block    = data.terraform_remote_state.database.outputs.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.eks_to_database.id
}

resource "aws_route" "database_to_private" {
  route_table_id            = data.terraform_remote_state.database.outputs.default_route_table_id
  destination_cidr_block    = module.vpc.vpc_cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.eks_to_database.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = false
  create_iam_role                          = var.eks_cluster_role_arn == ""
  iam_role_arn                             = var.eks_cluster_role_arn == "" ? null : var.eks_cluster_role_arn
  enable_irsa                              = var.enable_irsa_resources

  access_entries = var.eks_admin_principal_arn == "" ? {} : {
    lab_admin = {
      principal_arn = var.eks_admin_principal_arn
      type          = "STANDARD"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # No AWS Academy Lab, a role "voclabs" tem uma deny explícita para iam:GetRole
  # sobre si mesma, o que faz o KMS rejeitar qualquer key policy que a referencie
  # como principal (mesmo só como key administrator), com
  # "MalformedPolicyDocumentException: invalid principals". Como não há
  # requisito de compliance para cifrar os secrets do EKS com uma KMS key
  # própria neste laboratório, desabilita essa camada de encryption_config.
  cluster_encryption_config = {}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = var.node_instance_types
    disk_size      = var.node_disk_size
  }

  eks_managed_node_groups = {
    default = {
      min_size        = var.node_min_size
      max_size        = var.node_max_size
      desired_size    = var.node_desired_size
      create_iam_role = var.eks_node_role_arn == ""
      iam_role_arn    = var.eks_node_role_arn == "" ? null : var.eks_node_role_arn
    }
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "aws_load_balancer_controller_irsa" {
  count = var.enable_irsa_resources ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.cluster_name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_aws_load_balancer_controller && var.enable_irsa_resources ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller_irsa[0].iam_role_arn
  }

  depends_on = [module.eks, module.aws_load_balancer_controller_irsa]
}

# Escopo do External Secrets Operator: qualquer secret prefixado com o nome do
# cluster (cobre o secret "<cluster_name>/api" criado pelo repositório
# oficina-mecanica-fiap) mais o secret do RDS, lido automaticamente do state
# remoto do repositório oficina-mecanica-infra-banco-dados (local.rds_secret_arn).
# Usar um prefixo por nome em vez do ARN exato do secret da API evita uma
# dependência circular entre este repositório e o da aplicação principal.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = concat(
      ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.cluster_name}*"],
      local.rds_secret_arn == "" ? [] : [local.rds_secret_arn],
    )
  }
}

module "external_secrets_irsa" {
  count = var.enable_irsa_resources ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-external-secrets"

  role_policy_arns = {
    external_secrets = aws_iam_policy.external_secrets[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = local.common_tags
}

resource "aws_iam_policy" "external_secrets" {
  count = var.enable_irsa_resources ? 1 : 0

  name   = "${local.cluster_name}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json

  tags = local.common_tags
}

resource "helm_release" "external_secrets" {
  count = var.install_external_secrets_operator && var.enable_irsa_resources ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa[0].iam_role_arn
  }

  depends_on = [module.eks, module.external_secrets_irsa]
}

resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  namespace        = "kube-system"
  create_namespace = false

  depends_on = [module.eks]
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_github_actions_oidc ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  count = var.enable_github_actions_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name               = "${local.cluster_name}-github-actions-ecr"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    actions = ["ecr:GetAuthorizationToken"]

    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [aws_ecr_repository.api.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  count = var.enable_github_actions_oidc ? 1 : 0

  name   = "${local.cluster_name}-github-actions-ecr"
  role   = aws_iam_role.github_actions_ecr[0].id
  policy = data.aws_iam_policy_document.github_actions_ecr.json
}
