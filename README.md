<<<<<<< Updated upstream
# FCG Orchestration (Fase 3)

Repositorio de **orquestracao** da FIAP Cloud Games (Fase 3). Parte da base da Fase 2 (RabbitMQ, PostgreSQL, `docker-compose` e manifestos Kubernetes) e concentra aqui as novas capacidades obrigatorias do Tech Challenge: **API Gateway (Kong)**, **Observabilidade (Prometheus + Grafana)**, **MongoDB** e **Redis**.

> Cada microsservico vive no seu proprio repositorio `FIAPCloudGames-fase3-*`, partindo do codigo da Fase 2 ate que cada frente evolua o servico correspondente.

## Arquitetura

4 microsservicos independentes que se comunicam de forma **assincrona via RabbitMQ**:

| Servico | Papel | Banco | REST |
|---|---|:---:|:---:|
| users-api | Cadastro, login (JWT), autorizacao | PostgreSQL | Sim |
| catalog-api | CRUD de jogos, inicia compra, biblioteca | PostgreSQL | Sim |
| payments-api | Simula pagamento (consumidor de eventos) | PostgreSQL | So `/health` |
| notifications-api | "Envia" e-mails (log) | PostgreSQL | So `/health` |

Repos dos servicos:
- users-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-UsersAPI
- catalog-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-CatalogAPI
- payments-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-PaymentsAPI
- notifications-api: https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-NotificationsAPI

> `FiapCloudGames.Contracts` (https://github.com/pdelfino0/fcg-contracts) e o pacote com as classes de evento compartilhadas entre os servicos. E consumido via **NuGet** (`PackageReference` no `.csproj` de cada servico), **nao** precisa ser clonado localmente para rodar o Compose ou o k8s.

## Estrutura

```
FIAPCloudGames-fase3-Orchestration/   # este repo (nome padrao do git clone)
├── docker-compose.yml   # RabbitMQ + Postgres(4 bancos) + 4 servicos
├── .env.example         # variaveis do Compose (sem valores reais)
├── db/init.sql          # cria catalogdb, notificationsdb e paymentsdb
├── k8s/                 # manifestos agregados (kubectl apply -f k8s/)
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
└── FIAPCloudGames-fase3-NotificationsAPI/
```

```bash
mkdir fcg-fase3 && cd fcg-fase3

git clone https://github.com/andersonluizpereiradias/FIAPCloudGames-fase3-Orchestration.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-UsersAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-CatalogAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-PaymentsAPI.git
git clone https://github.com/joao-malvetoni-alta-horizon/FIAPCloudGames-fase3-NotificationsAPI.git
```

> Nao e preciso clonar `fcg-contracts`: ele e restaurado como pacote NuGet durante o `dotnet restore`/`docker build` de cada servico.

> Se voce **renomeou** as pastas localmente (ex.: `fcg-users-api`), copie `.env.example` para `.env` e ajuste `USERS_API_PATH`, `CATALOG_API_PATH`, etc.

## Como rodar com Docker

Pre-requisito: os repos de servico devem estar como **irmaos** deste, com os nomes padrao do clone (ou caminhos customizados no `.env`).

```bash
cd FIAPCloudGames-fase3-Orchestration
cp .env.example .env        # ajuste caminhos se renomeou pastas
docker-compose up --build
docker-compose ps           # todos healthy/running
```

Portas locais: users `8081`, catalog `8082`, payments `8083`, notifications `8084` (interno sempre `8080`).
Painel do RabbitMQ: http://localhost:15672 (fcg/fcg123).

### Testar os fluxos
1. **Cadastro:** `POST http://localhost:8081/api/users/register` -> ver log de boas-vindas no `notifications-api`.
2. **Compra:** iniciar compra no `catalog-api` (8082) -> pagamento aprovado -> jogo na biblioteca -> log de confirmacao.

## Como fazer deploy no Kubernetes (Minikube)

### Opcao automatizada (recomendada)

Requisitos: `docker`, `minikube`, `kubectl` e `make` instalados. No Windows, rode via **Git Bash** ou **WSL** (o `make` nao existe no PowerShell puro).

```bash
cp .env.example .env   # se ainda nao fez isso para o Compose

make k8s-up            # start do Minikube + build/load das 4 imagens + apply + espera os pods ficarem prontos
make k8s-status        # ve pods, deployments, services, configmaps e secrets
make k8s-ingress       # (opcional) habilita o Ingress e aplica o manifesto de ingress
make k8s-down          # derruba tudo (remove o namespace fcg)
```

`make help` lista todos os comandos disponiveis. Os scripts usados pelo Makefile ficam em `scripts/k8s/` e leem os caminhos dos repos irmaos do `.env` (mesmas variaveis do Compose: `USERS_API_PATH`, etc.).

O `minikube tunnel` e a edicao do arquivo de hosts (necessarios so para o Ingress) continuam manuais — ver o passo a passo abaixo.

### Passo a passo manual (o que o `make k8s-up` automatiza)

```bash
minikube start

# Build + carga das 4 imagens no cluster local
# (ajuste os caminhos se renomeou as pastas apos o clone)
docker build -t fcg/users-api:1.0 ../FIAPCloudGames-fase3-UsersAPI -f ../FIAPCloudGames-fase3-UsersAPI/src/FCG.API/Dockerfile
minikube image load fcg/users-api:1.0
docker build -t fcg/catalog-api:1.0 ../FIAPCloudGames-fase3-CatalogAPI -f ../FIAPCloudGames-fase3-CatalogAPI/src/CatalogAPI.API/Dockerfile
minikube image load fcg/catalog-api:1.0
docker build -t fcg/payments-api:1.0 ../FIAPCloudGames-fase3-PaymentsAPI -f ../FIAPCloudGames-fase3-PaymentsAPI/src/FCG.API/Dockerfile
minikube image load fcg/payments-api:1.0
docker build -t fcg/notifications-api:1.0 ../FIAPCloudGames-fase3-NotificationsAPI/NotificationsAPI -f ../FIAPCloudGames-fase3-NotificationsAPI/NotificationsAPI/src/Notifications.API/Dockerfile
minikube image load fcg/notifications-api:1.0

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
127.0.0.1 notifications.fcg.local
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

## Variaveis de ambiente por servico

| Variavel | users | catalog | payments | notifications | Origem |
|---|:---:|:---:|:---:|:---:|---|
| `ConnectionStrings__DefaultConnection` | Sim | Sim | Sim | Sim | Secret |
| `ConnectionStrings__RabbitMqConnection` | — | Sim | — | — | Secret |
| `RabbitMq__Host` | Sim | — | Sim | Sim | ConfigMap |
| `RabbitMq__Password` | Sim | — | Sim | Sim | Secret |
| `JwtSettings__SecretKey` | Sim | Sim | — | — | Secret |
| `ASPNETCORE_ENVIRONMENT` | Sim | Sim | Sim | Sim | ConfigMap |

> **Nota:** o `catalog-api` usa `ConnectionStrings__RabbitMqConnection` (URI `amqp://`) no lugar de `RabbitMq__*`. `users` e `catalog` compartilham a mesma `JwtSettings__SecretKey`. `payments` tem banco proprio (`paymentsdb`), mas nao usa JWT.

> **Secret** e apenas base64 (nao e cofre). Nao comite valores reais.
=======
# FIAP Cloud Games - Fase 3

Repositório responsável pela orquestração da arquitetura da FIAP Cloud Games
na Fase 3 do Tech Challenge.

## Projetos

- FIAPCloudGames-fase3-UsersAPI
- FIAPCloudGames-fase3-CatalogAPI
- FIAPCloudGames-fase3-PaymentsAPI
- FIAPCloudGames-fase3-NotificationsAPI

## Tecnologias

- .NET
- Kubernetes
- AWS
- AWS API Gateway
- AWS Lambda
- RabbitMQ
- Redis
- Prometheus
- Grafana
- NoSQL

## Arquitetura

Documentação em construção.

## Execução

Documentação em construção.

## Testes

Documentação em construção.
>>>>>>> Stashed changes
