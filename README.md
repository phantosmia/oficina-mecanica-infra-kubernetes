# oficina-mecanica-infra-kubernetes

Infraestrutura como código (Terraform) do **cluster Kubernetes (Amazon EKS)** do sistema de gestão de oficina mecânica — repositório 2 dos 4 exigidos pela Fase 3 do Tech Challenge (SOAT/FIAP).

## Status

**Placeholder** — implementação real pendente. Hoje, o Terraform que provisiona VPC, EKS, node group, ECR, IRSA e os add-ons Helm (AWS Load Balancer Controller, External Secrets Operator, metrics-server) ainda vive em [`infra/aws`](https://github.com/phantosmia/oficina-mecanica-fiap/tree/main/infra/aws) dentro do repositório `oficina-mecanica-fiap` (aplicação principal). A migração desse Terraform para este repositório será feita em uma etapa futura, com calma.

Use `oficina-mecanica-fiap/infra/aws` como referência do que este repositório deverá conter quando implementado.

## Tecnologias planejadas

- Terraform >= 1.6
- AWS EKS, VPC, ECR, IAM/IRSA
- Helm (AWS Load Balancer Controller, External Secrets Operator, metrics-server)
- GitHub Actions

## Escopo futuro

- VPC dedicada ao cluster (subnets públicas/privadas, NAT gateway).
- Cluster EKS + node group gerenciado com escalabilidade.
- Repositório ECR para a imagem da API.
- IAM Role for Service Accounts (IRSA) para AWS Load Balancer Controller e External Secrets Operator.
- Instalação via Helm do AWS Load Balancer Controller, External Secrets Operator e metrics-server (necessário para o HPA da aplicação).
- IAM Role OIDC para o GitHub Actions publicar imagens no ECR.
- Integração de rede com o repositório `oficina-mecanica-infra-banco-dados` (hoje com uma VPC própria e isolada) via CIDR autorizado ou VPC Peering.

## CI/CD

Workflow em [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml). Hoje só valida sintaxe/configuração do esqueleto (`terraform fmt -check`, `terraform validate`) em Pull Requests, e imprime uma mensagem de placeholder nos pushes para `homologacao`/`producao` — não há infraestrutura real para aplicar ainda.

### Regras de proteção

- Branch `main` protegida: sem commit direto, merge só via Pull Request.
- Branches `homologacao` e `producao` existem desde já, para já ter a estrutura de deploy por ambiente pronta quando a implementação real chegar.

## Repositórios relacionados

- [oficina-mecanica-fiap](https://github.com/phantosmia/oficina-mecanica-fiap) — aplicação principal (contém hoje o Terraform real de EKS/VPC/ECR em `infra/aws`).
- [oficina-mecanica-infra-banco-dados](https://github.com/phantosmia/oficina-mecanica-infra-banco-dados) — infraestrutura do banco de dados gerenciado (implementação real).
- [oficina-mecanica-lambda-auth](https://github.com/phantosmia/oficina-mecanica-lambda-auth) — function serverless de autenticação via CPF (placeholder).
