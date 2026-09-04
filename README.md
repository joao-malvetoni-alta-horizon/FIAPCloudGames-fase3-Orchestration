# FCG Orchestration (Fase 3)

Repositório de **orquestração** da FIAP Cloud Games (Fase 3). Parte da base da Fase 2 (RabbitMQ, PostgreSQL, `docker-compose` e manifestos Kubernetes) e concentra aqui as novas capacidades obrigatórias do Tech Challenge: **API Gateway (Kong)**, **Observabilidade (New Relic)**, **MongoDB**, **Redis** e a migração do `NotificationsAPI` para **Serverless (AWS Lambda)**.

> Cada microsserviço vive no seu próprio repositório `FIAPCloudGames-fase3-*`, partindo do código da Fase 2 até que cada frente evolua o serviço correspondente.

## Stack escolhida pelo grupo

| Requisito obrigatório | Ferramenta escolhida | Onde vive |
|---|---|---|
| API Gateway | Kong | `Orchestration` (manifestos `k8s/`) |
| Migração para Serverless | AWS Lambda (SNS + SQS) | Repositório próprio `FIAPCloudGames-fase3-NotificationsAPI` |
| Observabilidade | New Relic (Opção B: métricas, logs e traces) | `UsersAPI`, `CatalogAPI`, `PaymentsAPI` e a função Lambda |
| NoSQL | DynamoDB (dados de notificação) | Função Lambda / `FIAPCloudGames-fase3-NotificationsAPI` |
| Cache distribuído | Redis | Microsserviço(s) HTTP |

## Arquitetura

3 microsserviços HTTP independentes que se comunicam de forma **assíncrona** (RabbitMQ entre `catalog-api` -> `payments-api`; SNS de `users-api`/`payments-api` para a Lambda de notificações), mais uma função serverless:

| Serviço | Papel | Banco | REST |
|---|---|:---:|:---:|
| users-api | Cadastro, login (JWT), autorização | PostgreSQL | Sim |
| catalog-api | CRUD de jogos, inicia compra, biblioteca | PostgreSQL | Sim |
| payments-api | Simula pagamento (consumidor de eventos) | PostgreSQL | Só `/health` |

O antigo `notifications-api` (container 24/7 que só consumia eventos do RabbitMQ) foi **migrado para uma função AWS Lambda** — não faz mais parte do `docker-compose`/`k8s` deste repositório. Ver a seção [Serverless (NotificationsAPI)](#serverless-notificationsapi) abaixo.

Repos dos serviços:
- users-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-UsersAPI
- catalog-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-CatalogAPI
- payments-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-PaymentsAPI
- notifications (serverless): https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-NotificationsAPI

> `FiapCloudGames.Contracts` (https://github.com/pdelfino0/fcg-contracts) é o pacote com as classes de evento compartilhadas entre os serviços. É consumido via **NuGet** (`PackageReference` no `.csproj` de cada serviço), **não** precisa ser clonado localmente para rodar o Compose ou o k8s.

## Estrutura

```
FIAPCloudGames-fase3-Orchestration/   # este repo (nome padrao do git clone)
├── docker-compose.yml   # RabbitMQ + Postgres (2 bancos) + 3 microsservicos HTTP
├── .env.example         # variaveis do Compose (sem valores reais)
├── db/init.sql          # cria catalogdb e paymentsdb
├── k8s/                 # manifestos agregados (kubectl apply -f k8s/)
├── observability/       # secret/manifestos de New Relic
├── docs/                # documentacao de observabilidade
└── templates/           # modelos de Dockerfile e /k8s por servico
```

## Como clonar (layout esperado)

Clone os **5 repos** na **mesma pasta pai**. O `docker-compose` assume os nomes padrao gerados pelo GitHub:

```
pasta-pai/
├── FIAPCloudGames-fase3-Orchestration/   # este repo
├── FIAPCloudGames-fase3-UsersAPI/
├── FIAPCloudGames-fase3-CatalogAPI/
├── FIAPCloudGames-fase3-PaymentsAPI/
└── FIAPCloudGames-fase3-NotificationsAPI/   # codigo + IaC da funcao Lambda (nao entra no compose/k8s)
```

```bash
mkdir fcg-fase3 && cd fcg-fase3

git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-Orchestration.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-UsersAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-CatalogAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-PaymentsAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-NotificationsAPI.git
```

> Não é preciso clonar `fcg-contracts`: ele é restaurado como pacote NuGet durante o `dotnet restore`/`docker build` de cada serviço.

> Se você **renomeou** as pastas localmente (ex.: `fcg-users-api`), copie `.env.example` para `.env` e ajuste `USERS_API_PATH`, `CATALOG_API_PATH`, etc.

## Como rodar com Docker

Pré-requisito: os repos de serviço devem estar como **irmãos** deste, com os nomes padrão do clone (ou caminhos customizados no `.env`).

```bash
cd FIAPCloudGames-fase3-Orchestration
cp .env.example .env        # ajuste caminhos se renomeou pastas
docker-compose up --build
docker-compose ps           # todos healthy/running
```

Portas locais: users `8081`, catalog `8082`, payments `8083` (interno sempre `8080`).
Painel do RabbitMQ: http://localhost:15672 (fcg/fcg123).

### Testar os fluxos
1. **Cadastro:** `POST http://localhost:8081/api/users/register` -> publica `UserRegisteredEvent` no SNS (`fcg-user-events`), acionando a Lambda de notificações. Requer `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` válidos no `.env` (ver `.env.example`); sem eles, a publicação falha silenciosamente (log de warning) e o cadastro continua normal.
2. **Compra:** iniciar compra no `catalog-api` (8082) -> `OrderPlacedEvent` via RabbitMQ -> `payments-api` processa e publica `PaymentProcessedEvent` em dois transportes: RabbitMQ (de volta pro `catalog-api`, libera o jogo na biblioteca se aprovado) e SNS (`fcg-payment-events`, aciona a Lambda de notificações).

## Como fazer deploy no Kubernetes (Minikube)

### Opção automatizada (recomendada)

Requisitos: `docker`, `minikube`, `kubectl` e `make` instalados. No Windows, rode via **Git Bash** ou **WSL** (o `make` não existe no PowerShell puro).

```bash
cp .env.example .env   # se ainda nao fez isso para o Compose

make k8s-up            # start do Minikube + build/load das 3 imagens + apply + espera os pods ficarem prontos
make k8s-status        # ve pods, deployments, services, configmaps e secrets
make k8s-ingress       # (opcional) habilita o Ingress e aplica o manifesto de ingress
make k8s-down          # derruba tudo (remove o namespace fcg)
```

`make help` lista todos os comandos disponíveis. Os scripts usados pelo Makefile ficam em `scripts/k8s/` e leem os caminhos dos repos irmãos do `.env` (mesmas variáveis do Compose: `USERS_API_PATH`, etc.).

O `minikube tunnel` e a edição do arquivo de hosts (necessários só para o Ingress) continuam manuais — ver o passo a passo abaixo.

### Passo a passo manual (o que o `make k8s-up` automatiza)

```bash
minikube start

# Build + carga das 3 imagens no cluster local
# (ajuste os caminhos se renomeou as pastas apos o clone)
docker build -t fcg/users-api:1.0 ../FIAPCloudGames-fase3-UsersAPI -f ../FIAPCloudGames-fase3-UsersAPI/src/FCG.API/Dockerfile
minikube image load fcg/users-api:1.0
docker build -t fcg/catalog-api:1.0 ../FIAPCloudGames-fase3-CatalogAPI -f ../FIAPCloudGames-fase3-CatalogAPI/src/CatalogAPI.API/Dockerfile
minikube image load fcg/catalog-api:1.0
docker build -t fcg/payments-api:1.0 ../FIAPCloudGames-fase3-PaymentsAPI -f ../FIAPCloudGames-fase3-PaymentsAPI/src/FCG.API/Dockerfile
minikube image load fcg/payments-api:1.0

# Aplica tudo (a numeracao garante a ordem)
kubectl apply -f k8s/

# Verifica
kubectl get pods -n fcg
kubectl get deployments,services,configmaps,secrets -n fcg

# Acessar uma API de fora do cluster
kubectl port-forward service/users-api 8081:8080 -n fcg
```

## Expor as APIs com Ingress (alternativa ao port-forward)

O `port-forward` é só para teste manual (uma porta, um serviço, uma sessão). Para expor **todas** as APIs de uma vez, com um único ponto de entrada, usamos um `Ingress` (`k8s/30-ingress.yaml`), que roteia por hostname para cada Service.

> **Kong.** A introdução do Kong como porta de entrada única (validação de JWT + roteamento para `users-api`/`catalog-api`) está sendo desenvolvida na branch `feat/api-gateway` deste repositório, com manifestos próprios (`k8s/03-kong-config.yaml`, `k8s/24-kong.yaml`, `kong/kong.yml`). Até o merge para `main`, o roteamento externo segue pelo Ingress nginx descrito abaixo.

```bash
# 1. Habilitar o controller de Ingress do Minikube (só uma vez por cluster)
minikube addons enable ingress

# 2. Esperar o controller ficar Running (pode levar ~1 min)
kubectl get pods -n ingress-nginx --watch

# 3. Aplicar o manifesto do Ingress (se já rodou "kubectl apply -f k8s/" antes, so isso já basta)
kubectl apply -f k8s/30-ingress.yaml

# 4. Confirmar que o Ingress recebeu um endereco
kubectl get ingress -n fcg
```

Depois, em outro terminal (deixe rodando, exige permissao de administrador no Windows):

```bash
minikube tunnel
```

Isso expõe o controller do Ingress em `localhost:80`. Falta só resolver os hostnames: edite o arquivo de hosts do Windows (`C:\Windows\System32\drivers\etc\hosts`, como administrador) e adicione:

```
127.0.0.1 users.fcg.local
127.0.0.1 catalog.fcg.local
127.0.0.1 payments.fcg.local
127.0.0.1 rabbitmq.fcg.local
```

Agora cada API responde no seu hostname, na porta 80 (sem porta na URL), com as mesmas rotas de sempre:

```bash
curl -X POST http://users.fcg.local/api/users/register `
  -H "Content-Type: application/json" `
  -d '{"name":"Teste Ingress","email":"ingress@teste.com","password":"Senha123!"}'

curl http://catalog.fcg.local/api/v1/games
```

O painel de gestão do RabbitMQ também sai pelo mesmo túnel, em `http://rabbitmq.fcg.local` (login `fcg` / `fcg123`).

> **Por que por hostname e não por caminho (`/users`, `/catalog`)?** Cada API já tem seus próprios prefixos de rota (`/api/users/...`, `/api/v1/games`, etc.), diferentes entre si. Rotear por path exigiria reescrever a URL antes de repassar pro serviço (`rewrite-target`), o que complica sem necessidade aqui. Rotear por hostname mantém as rotas originais intactas — cada domínio aponta pra um Service só.

## Serverless (NotificationsAPI)

O `NotificationsAPI` da Fase 2 (container ASP.NET Core rodando 24/7 no Kubernetes, só para consumir eventos do RabbitMQ) foi **migrado para uma função AWS Lambda**, atendendo ao requisito obrigatório de "Migração para Arquitetura Serverless" da Fase 3.

- **Repositório próprio (código + IaC):** https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-NotificationsAPI
- **Infraestrutura como código:** AWS SAM (`template.yaml` na raiz daquele repositório).
- **Arquitetura:** `UsersAPI`/`PaymentsAPI` publicam `UserRegisteredEvent`/`PaymentProcessedEvent` num tópico **SNS**, que entrega numa fila **SQS** (com DLQ), que aciona a **Lambda** correspondente — sem nenhum componente rodando continuamente.
- **Persistência:** DynamoDB (`fcg-notifications`), atendendo também o requisito obrigatório de NoSQL.
- **Observabilidade:** OpenTelemetry exportando para o New Relic (traces e, em configuração, métricas/logs), consistente com a escolha de Opção B (New Relic) do grupo.

Recursos provisionados na AWS (conta usada pelo grupo, região `us-east-1`):

| Recurso | Nome |
|---|---|
| Stack CloudFormation | `fcg-notifications-serverless` |
| Funções Lambda | `fcg-notifications-user-registered`, `fcg-notifications-payment-processed` |
| Tópicos SNS | `fcg-user-events`, `fcg-payment-events` |
| Filas SQS (+ DLQ) | `fcg-notifications-user-registered`, `fcg-notifications-payment-processed` |
| Tabela DynamoDB | `fcg-notifications` |

`UsersAPI` e `PaymentsAPI` publicam `UserRegisteredEvent`/`PaymentProcessedEvent` diretamente nos tópicos SNS acima (ver `Sns__TopicArn` na tabela abaixo) — o fluxo é acionado por qualquer cadastro de usuário ou pagamento processado real do sistema, sem precisar de publicação manual via CLI/console. O RabbitMQ continua em uso só para o fluxo `catalog-api` -> `payments-api` (`OrderPlacedEvent`), que não muda com essa migração.

## Variaveis de ambiente por servico

| Variavel | users | catalog | payments | Origem |
|---|:---:|:---:|:---:|---|
| `ConnectionStrings__DefaultConnection` | Sim | Sim | Sim | Secret |
| `ConnectionStrings__RabbitMqConnection` | — | Sim | — | Secret |
| `RabbitMq__Host` | — | — | Sim | ConfigMap |
| `RabbitMq__Password` | — | — | Sim | Secret |
| `Sns__TopicArn` | Sim | — | Sim | ConfigMap |
| `AWS_REGION` | Sim | — | Sim | ConfigMap |
| `AWS_ACCESS_KEY_ID` | Sim | — | Sim | Secret |
| `AWS_SECRET_ACCESS_KEY` | Sim | — | Sim | Secret |
| `JwtSettings__SecretKey` | Sim | Sim | — | Secret |
| `ASPNETCORE_ENVIRONMENT` | Sim | Sim | Sim | ConfigMap |
| `NEW_RELIC_LICENSE_KEY` | Sim | Sim | Sim | Secret (`observability/new-relic-secret.yaml`) |

> **Nota:** o `catalog-api` usa `ConnectionStrings__RabbitMqConnection` (URI `amqp://`) no lugar de `RabbitMq__*`. `users` e `catalog` compartilham a mesma `JwtSettings__SecretKey`. `payments` tem banco proprio (`paymentsdb`), nao usa JWT, e publica `PaymentProcessedEvent` em dois transportes: RabbitMQ (de volta pro `catalog-api`, libera o jogo na biblioteca) e SNS (para a Lambda do NotificationsAPI). As credenciais AWS sao só para o SNS; sem elas essa publicacao falha silenciosamente (log de warning) e o restante do fluxo (RabbitMQ/HTTP) continua normal.

> **Secret** e apenas base64 (nao e cofre). Nao comite valores reais.

## Observabilidade (New Relic)

O grupo optou pela **Opção B** do enunciado (plataforma de APM gerenciada): **New Relic**, cobrindo os três pilares (métricas, logs e traces) em `UsersAPI`, `CatalogAPI`, `PaymentsAPI` e na função serverless. Detalhes em [`docs/observability.md`](docs/observability.md). A license key é injetada via Kubernetes Secret (`observability/new-relic-secret.yaml`), nunca commitada em texto puro no código-fonte, conforme exigido pelo enunciado para a Opção B.
