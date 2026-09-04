<<<<<<< Updated upstream
# FCG Orchestration (Fase 3)

Repositorio de **orquestracao** da FIAP Cloud Games (Fase 3). Parte da base da Fase 2 (RabbitMQ, PostgreSQL, `docker-compose` e manifestos Kubernetes) e concentra aqui as novas capacidades obrigatorias do Tech Challenge: **API Gateway (Kong)** (feito, cobrindo `users-api` e `catalog-api` -- ver [API Gateway (Kong)](#api-gateway-kong)), **Observabilidade (Prometheus + Grafana)**, **MongoDB** e **Redis**.

> **Com pressa?** O gateway responde em `http://localhost:8000` (Docker) ou `http://gateway.fcg.local` (Kubernetes com Ingress). A tabela de [onde chamar o gateway](#onde-chamar-o-gateway) tem a URL base de cada forma de subir o projeto.

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
├── docker-compose.yml   # RabbitMQ + Postgres(4 bancos) + 4 servicos + Kong
├── .env.example         # variaveis do Compose (sem valores reais)
├── db/init.sql          # cria catalogdb, notificationsdb e paymentsdb
├── kong/                # API Gateway: config declarativa (unica fonte de verdade)
│   ├── kong.yml             # services, routes, plugins e credencial JWT
│   └── render-and-start.sh  # injeta segredo/issuer e sobe o Kong
├── k8s/                 # manifestos agregados (kubectl apply -f k8s/)
├── scripts/             # automacao (k8s/ e kong/)
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

Portas locais: **gateway (Kong) `8000`**, users `8081`, catalog `8082`, payments `8083`, notifications `8084` (interno sempre `8080`).
Painel do RabbitMQ: http://localhost:15672 (fcg/fcg123).

> As portas diretas (8081-8084) continuam abertas para debug, mas o caminho "oficial" de `users` e `catalog` agora e o gateway na `8000` -- ver [API Gateway (Kong)](#api-gateway-kong).

### Testar os fluxos

Tudo pelo gateway (`localhost:8000`):

```bash
# 1. Cadastro (rota anonima) -> ver log de boas-vindas no notifications-api
curl -s -X POST http://localhost:8000/users/api/users/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@fcg.com","password":"Senha123!"}'

# 2. Login (rota anonima) -> guarda o token
TOKEN=$(curl -s -X POST http://localhost:8000/users/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"teste@fcg.com","password":"Senha123!"}' | jq -r .accessToken)

# 3. Catalogo (rota protegida: o gateway valida o JWT antes de encaminhar)
curl -s http://localhost:8000/catalog/api/v1/games -H "Authorization: Bearer $TOKEN"
```

3. **Compra:** iniciar compra no `catalog-api` pelo gateway -> pagamento aprovado -> jogo na biblioteca -> log de confirmacao no `notifications-api`.

## API Gateway (Kong)

Ponto de entrada unico das APIs. Roda em modo **DB-less** (sem Postgres proprio): toda a configuracao vem do arquivo declarativo `kong/kong.yml`.

**Escopo atual: `users-api` e `catalog-api`.** `payments-api` e `notifications-api` sao consumidores de evento (so expoem `/health`), entao nao entram no gateway.

`kong/kong.yml` e a **unica fonte de verdade**: o `docker-compose` monta a pasta `kong/` como volume, e no Kubernetes o mesmo conteudo e empacotado no ConfigMap `k8s/03-kong-config.yaml`, que e **gerado** por `make kong-config` (nao edite o ConfigMap a mao).

### Onde chamar o gateway

O Kong sempre escuta na porta **8000** *dentro* da rede (do Compose ou do cluster). O que muda entre os ambientes e so como voce alcanca essa porta de fora:

| Como voce subiu | URL base do gateway | Precisa de que |
|---|---|---|
| `docker-compose up` | `http://localhost:8000` | nada, a porta ja e publicada |
| k8s + `port-forward` | `http://localhost:8000` | `kubectl port-forward service/kong-proxy 8000:8000 -n fcg` rodando em outro terminal |
| k8s + Ingress | `http://gateway.fcg.local` (porta 80) | `make k8s-ingress` + `minikube tunnel` + entrada no arquivo de hosts |

Trocar de ambiente e trocar so a URL base -- os caminhos (`/users/...`, `/catalog/...`) sao identicos nos tres casos:

```bash
GATEWAY=http://localhost:8000          # Compose ou port-forward
# GATEWAY=http://gateway.fcg.local     # k8s com Ingress

curl -s -X POST $GATEWAY/users/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"teste@fcg.com","password":"Senha123!"}'
```

### Rotas expostas

| Rota no gateway | Vai para | JWT no gateway |
|---|---|:---:|
| `POST /users/api/auth/login` | `users-api:8080/api/auth/login` | nao (e ela que **emite** o token) |
| `POST /users/api/users/register` | `users-api:8080/api/users/register` | nao (cadastro e anonimo) |
| `/users/**` (resto, hoje `/api/admin/users/**`) | `users-api:8080/**` | **sim** |
| `GET /catalog/swagger/...` | `catalog-api:8080/swagger/...` | nao |
| `/catalog/**` (resto) | `catalog-api:8080/**` | **sim** |

O `strip_path` do Kong remove o prefixo, entao as rotas originais dos servicos continuam valendo:

```
GET  http://localhost:8000/catalog/api/v1/games      ->  GET  http://catalog-api:8080/api/v1/games
POST http://localhost:8000/users/api/users/register  ->  POST http://users-api:8080/api/users/register
```

**A postura e "nega por padrao".** As duas rotas anonimas do `users-api` sao liberadas endpoint a endpoint *e por metodo* (`POST`/`OPTIONS`); qualquer outro caminho ou verbo cai na rota catch-all `/users`, que exige JWT. Um endpoint novo no `users-api` ja nasce protegido no gateway, sem editar nada:

```bash
curl -i http://localhost:8000/users/api/admin/users        # 401 - catch-all pede token
curl -i -X GET http://localhost:8000/users/api/auth/login  # 401 - GET nao esta liberado, cai na catch-all
```

> O plugin `jwt` confere **assinatura, `exp` e issuer** -- nao papel. O `AdminOnly` de `/api/admin/users/**` continua sendo decidido pelo `users-api`, que le a claim de role do token.

<details>
<summary><b>Detalhe de implementacao: por que ha varios <code>services</code> do Kong por microsservico</b></summary>

`strip_path: true` remove do upstream **todo o prefixo que a rota casou**, nao apenas o primeiro segmento. Isso derruba a tentativa mais obvia de liberar um endpoint especifico:

```yaml
# ERRADO - verificado no Kong 3.9
- name: users-api
  url: http://users-api:8080
  routes:
    - name: users-login
      paths: [/users/api/auth/login]
      strip_path: true
# POST /users/api/auth/login  ->  POST /   (sobrou nada depois do strip)
```

A correcao e por o caminho do upstream na **URL do service**; o que sobra do strip e concatenado depois:

```yaml
# CERTO
- name: users-api-login
  url: http://users-api:8080/api/auth/login   # <- caminho do upstream aqui
  routes:
    - name: users-login
      paths: [/users/api/auth/login]
      strip_path: true
# POST /users/api/auth/login  ->  POST /api/auth/login
```

Por isso um "service" do Kong aqui e um **endpoint de upstream**, nao um microsservico inteiro: `users-api-login`, `users-api-register` e `users-api` (catch-all) apontam todos para o mesmo host. A alternativa seria um plugin de rewrite (`request-transformer`) em cada rota -- mais peca movel para o mesmo resultado.

Rotas de prefixo amplo (`/users`, `/catalog`) nao sofrem disso: o strip deixa o resto do caminho intacto.

</details>

### Plugins habilitados

| Plugin | Escopo | Para que |
|---|---|---|
| `jwt` | rotas `/users/**` e `/catalog/**` | valida assinatura HS256, `exp` e o issuer do token |
| `rate-limiting` | rotas de login e register | **20 req/min e 200 req/h por IP** (anti brute-force) |
| `rate-limiting` | global | 120 req/min e 2000 req/h (`policy: local`) |
| `cors` | global | libera o consumo pelo front |
| `correlation-id` | global | gera/propaga `X-Correlation-ID` e devolve na resposta |
| `request-size-limiting` | global | corta payloads acima de 10 MB |
| `prometheus` | global | metricas em `:8100/metrics` (pronto para a frente de observabilidade) |

O Kong aplica **so a instancia mais especifica** de cada plugin (rota > servico > global). Por isso o limite apertado das rotas de login/register *substitui* o global em vez de somar -- da para ver nos headers da resposta:

```bash
curl -s -D - -o /dev/null -X POST http://localhost:8000/users/api/auth/login -d '{}' | grep -i ratelimit
#   X-RateLimit-Limit-Minute: 20     <- rota de login
curl -s -D - -o /dev/null http://localhost:8000/catalog/api/v1/games | grep -i ratelimit
#   X-RateLimit-Limit-Minute: 120    <- global
```

> `policy: local` conta por instancia do Kong. Com 2 replicas no k8s, o limite efetivo e ~2x o configurado. Trocar para `policy: redis` quando o Redis entrar no projeto.
>
> No k8s, o Kong so ve o IP real do cliente porque o Deployment define `KONG_TRUSTED_IPS` (faixas privadas) e `KONG_REAL_IP_HEADER=X-Forwarded-For`. Sem isso, o peer TCP seria sempre o pod do `ingress-nginx` e **todo o trafego externo contaria como um unico IP** -- um usuario esbarrando no limite do login derrubaria o login de todos. `KONG_REAL_IP_RECURSIVE` fica em `off` de proposito: assim vale a *ultima* entrada do `X-Forwarded-For` (a que o ingress acabou de acrescentar), e nao um valor que o cliente possa falsificar.

### Autenticacao: quem emite e quem valida

O **users-api emite** o JWT; o gateway apenas **valida** antes de encaminhar. O `catalog-api` continua validando o token por conta dele -- e defesa em profundidade, nao substituicao.

O Kong precisa saber **qual credencial** usar para checar a assinatura, e descobre isso pela claim `iss` do token.

Na Fase 2 o `JwtTokenService` do users-api montava o token **sem** issuer (`new JwtSecurityToken(claims:, expires:, signingCredentials:)`), entao o gateway rejeitava tudo com `401 {"message":"No mandatory 'iss' in claims"}`. O users-api passou a emitir a claim; a mudanca e retrocompativel, porque users-api e catalog-api usam `ValidateIssuer = false` e seguem ignorando o valor.

O issuer vem de **uma variavel unica**, lida pelos dois lados -- e o que impede os dois de dessincronizarem:

| Onde | Variavel | Papel |
|---|---|---|
| users-api | `JwtSettings__Issuer` | **emite** a claim `iss` |
| kong | `JWT_ISSUER` | **valida** a claim `iss` |

Ambas saem de `JWT_ISSUER` (default `FCG`): do `.env` no Compose, da key `JWT_ISSUER` do ConfigMap `fcg-config` no k8s.

Para mudar o issuer, **nao edite o `kong/kong.yml`** -- mexa so na variavel:

```bash
# Compose: ajuste JWT_ISSUER no .env e recrie os dois
docker-compose up -d --force-recreate users-api kong

# k8s: ajuste a key JWT_ISSUER e reinicie os dois
kubectl apply -f k8s/01-configmap.yaml
kubectl rollout restart deployment/users-api deployment/kong -n fcg
```

Conferindo a claim de um token real:

```bash
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .iss    # "FCG"
```

> **Reiniciar so um dos dois quebra o login via gateway.** Se mudar `JWT_ISSUER` e reiniciar apenas o users-api (ou apenas o Kong), os tokens novos deixam de casar com a credencial do gateway e toda chamada autenticada volta `401 No credentials found for given 'iss'`.

### Onde fica o segredo

O `JWT_SECRET_KEY` (mesma chave HMAC de users e catalog) **nao** esta versionado no `kong/kong.yml` -- o arquivo traz o placeholder `__JWT_SECRET_KEY__`, que o `kong/render-and-start.sh` substitui na subida do container, lendo a variavel de ambiente. A origem do valor depende do ambiente:

| Ambiente | De onde vem o segredo |
|---|---|
| Compose | `JWT_SECRET_KEY` no `.env` |
| Kubernetes | key `JwtSettings__SecretKey` do Secret `fcg-secrets` (`k8s/02-secret.yaml`) |

A key e a **mesma** que alimenta o `users-api` (que emite o token) e o `catalog-api` (que tambem valida): uma entrada no Secret, tres consumidores. Trocar a chave e editar `k8s/02-secret.yaml` e reiniciar os tres -- se reiniciar so parte deles, os tokens novos deixam de casar com quem ficou com a chave antiga:

```bash
kubectl apply -f k8s/02-secret.yaml
kubectl rollout restart deployment/users-api deployment/catalog-api deployment/kong -n fcg
```

Por que um script de render, e nao interpolacao: o Kong DB-less nao expande variaveis de ambiente no YAML declarativo, e o campo `jwt_secrets.secret` nao aceita referencia de vault (`{vault://env/...}`) -- a referencia seria usada como a propria chave HMAC e toda validacao falharia com `Invalid signature`.

Cuidados que o `render-and-start.sh` toma com o valor (e o motivo de cada um):

| Cuidado | Por que |
|---|---|
| o valor vai por `ENVIRON` do `awk`, nao por `awk -v` | `argv` e legivel por qualquer processo do container via `ps`/`/proc` |
| `unset JWT_SECRET_KEY` antes do `exec` | tira o segredo de `/proc/1/environ`, visivel a quem consiga um `kubectl exec` |
| arquivo renderizado criado com `umask 077` (fica `0600`) | ele contem o segredo em texto |
| substituicao literal (`index`/`substr`) e valor emitido como escalar YAML entre aspas simples | segredo com `&`, `\|`, `"`, `\` ou `$` corromperia um `sed` ou o YAML, gerando uma chave HMAC silenciosamente errada |

No k8s, a **Admin API escuta apenas em `127.0.0.1`** dentro do pod (`KONG_ADMIN_LISTEN`), porque ela devolve a credencial ja resolvida:

```bash
kubectl port-forward deploy/kong 8001:8001 -n fcg     # em outro terminal
curl -s localhost:8001/consumers/fcg-users-api/jwt | jq '.data[0]'
#   ...,"key":"FCG","secret":"6a8a56f4..."     <- o segredo, em texto
```

Sem esse bind, qualquer pod do cluster leria o segredo do JWT com um `curl`. O `port-forward` continua funcionando porque ele entra na **network namespace do pod** e disca o `127.0.0.1` de dentro dele -- e por isso a Admin API segue acessivel para quem ja tem credencial no cluster, e so para essa pessoa.

### Testando o gateway

Trocando `GATEWAY` conforme a tabela de [onde chamar o gateway](#onde-chamar-o-gateway), o roteiro e o mesmo nos tres ambientes:

```bash
GATEWAY=http://localhost:8000

# 0. O gateway carregou a config declarativa?
#    (Compose: porta ja publicada. k8s: kubectl port-forward service/kong-proxy 8100:8100 -n fcg)
curl -s http://localhost:8100/status/ready     # {"message":"ready"}

# 1. Cadastro e login: rotas ANONIMAS no gateway
curl -s -X POST $GATEWAY/users/api/users/register -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@fcg.com","password":"Senha123!"}'

TOKEN=$(curl -s -X POST $GATEWAY/users/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"teste@fcg.com","password":"Senha123!"}' | jq -r .accessToken)

# 2. Rota protegida COM token
curl -i $GATEWAY/catalog/api/v1/games -H "Authorization: Bearer $TOKEN"
curl -i $GATEWAY/users/api/admin/users -H "Authorization: Bearer $TOKEN"

# 3. Sem token: o gateway barra antes de encostar no servico
curl -i $GATEWAY/catalog/api/v1/games      # 401 {"message":"Unauthorized"}
curl -i $GATEWAY/users/api/admin/users     # 401 {"message":"Unauthorized"}
```

> No passo 2, `/users/api/admin/users` com o token de um usuario recem-cadastrado responde **403**: o gateway aprovou o token (assinatura e `exp` validos) e o `users-api` recusou o papel. Um 403 ali e sinal de que o gateway fez a parte dele -- diferente do 401, que nem sai do Kong.

Comportamento do plugin `jwt` (verificado no Kong 3.9 com tokens forjados):

| Requisicao | Resposta do gateway |
|---|---|
| sem `Authorization` | `401 {"message":"Unauthorized"}` |
| assinado com outro segredo | `401 {"message":"Invalid signature"}` |
| `iss` diferente do configurado | `401 {"message":"No credentials found for given 'iss'"}` |
| `exp` no passado | `401 {"exp":"token expired"}` |
| token valido | encaminhado ao servico |

E o roteamento (o que o servico realmente recebe):

| Chamada no gateway | Chega no upstream como |
|---|---|
| `POST /users/api/auth/login` | `POST users-api:8080/api/auth/login` |
| `POST /users/api/users/register` | `POST users-api:8080/api/users/register` |
| `GET /users/api/admin/users` | `GET users-api:8080/api/admin/users` |
| `GET /catalog/api/v1/games` | `GET catalog-api:8080/api/v1/games` |
| `GET /catalog/swagger/index.html` | `GET catalog-api:8080/swagger/index.html` |

> **Swagger:** os dois servicos registram o Swagger apenas quando `ASPNETCORE_ENVIRONMENT=Development` (`if (app.Environment.IsDevelopment())` no `Program.cs`). Compose e k8s rodam em `Production`, entao `/catalog/swagger` responde **404 vindo do servico** -- a rota do gateway esta certa, o Swagger e que nao existe naquele ambiente. Para explorar o contrato, suba o servico com `ASPNETCORE_ENVIRONMENT=Development` e use a porta direta (`http://localhost:8082/swagger`): o `swagger.json` gerado pelo ASP.NET aponta para o caminho absoluto `/swagger/v1/swagger.json`, sem o prefixo `/catalog`, entao o "Try it out" pelo gateway nao carregaria o schema.

### Portas do gateway

| Porta | O que e | Exposicao no Compose | Exposicao no k8s |
|---|---|---|---|
| `8000` | proxy (entrada das APIs) | `0.0.0.0` | Service `kong-proxy` + Ingress |
| `8001` | Admin API (read-only no DB-less) | so `127.0.0.1` do host | so `127.0.0.1` do **pod** |
| `8100` | `/status/ready` e `/metrics` | so `127.0.0.1` do host | Service `kong-proxy` (fora do Ingress) |

```bash
# Compose
curl -s http://localhost:8001/routes | jq '.data[].paths'   # rotas carregadas
curl -s http://localhost:8100/metrics | grep kong_http_requests_total

# k8s: a 8001 nao sai do pod, entao va por port-forward (em outro terminal)
kubectl port-forward deploy/kong 8001:8001 -n fcg
curl -s http://localhost:8001/routes | jq '.data[].paths'
```

> Nao tente `kubectl exec ... -- curl`: a imagem `kong:3.9` **nao traz `curl` nem `wget`** (so `perl` e `resty`). Para inspecionar o gateway de fora, use `port-forward`.

> No Compose a Admin API escuta em `0.0.0.0` de proposito: o mapeamento de portas do Docker chega pelo IP do container, entao com bind no loopback a publicacao nao funcionaria. Quem limita o acesso ali e a propria publicacao, presa em `127.0.0.1` do host.

### No Kubernetes

O Kong sobe como `Deployment` (2 replicas) + `Service` ClusterIP `kong-proxy`, e o Ingress ganhou o host `gateway.fcg.local`:

```bash
make kong-config     # se editou kong/kong.yml (o make k8s-deploy tambem faz isso)
make k8s-deploy
make k8s-ingress     # exige o passo do minikube tunnel + arquivo de hosts

curl http://gateway.fcg.local/catalog/api/v1/games -H "Authorization: Bearer $TOKEN"
```

Sem Ingress, via port-forward (deixe rodando em outro terminal):

```bash
kubectl port-forward service/kong-proxy 8000:8000 -n fcg
# agora o gateway responde em http://localhost:8000, com os mesmos caminhos
```

> **Editou `kong/kong.yml`? O `make k8s-deploy` cuida do rollout.** O Kong le a config declarativa **uma vez, no startup** -- trocar o ConfigMap nao afeta os pods que ja estao rodando. Para resolver isso, o `make kong-config` grava o hash das fontes numa annotation do ConfigMap e o `scripts/k8s/deploy.sh` copia esse hash para o pod template do Deployment. Como o `kubectl patch` e idempotente, os pods rolam quando (e somente quando) a config muda. Se aplicar os manifestos na mao, o restart e por sua conta:
>
> ```bash
> kubectl rollout restart deployment/kong -n fcg
> ```

### Adicionando um servico novo ao gateway

Em `kong/kong.yml`, dois blocos em `services`: a catch-all protegida e uma liberacao por endpoint, se houver rota anonima.

```yaml
  # 1) Endpoint anonimo: o caminho do upstream vai na URL DO SERVICE.
  #    (Nao ponha o caminho completo so na rota com strip_path -- o strip
  #     removeria o caminho inteiro e o upstream receberia "/".)
  - name: novo-api-publico
    url: http://novo-api:8080/api/publico
    routes:
      - name: novo-publico
        paths: [/novo/api/publico]
        strip_path: true
        methods: [POST, OPTIONS]        # so este verbo passa sem token

  # 2) Catch-all: tudo o mais do prefixo /novo exige JWT.
  - name: novo-api
    url: http://novo-api:8080
    routes:
      - name: novo-protegido
        paths: [/novo]
        strip_path: true
        plugins:
          - name: jwt
            config: { key_claim_name: iss, claims_to_verify: [exp] }
```

Depois: `make kong-config` + `make k8s-deploy` (k8s) ou `docker-compose up -d --force-recreate kong` (Compose).

Vale conferir o roteamento no log do Kong -- ele mostra a URL exata que foi para o upstream:

```bash
docker-compose logs kong | grep upstream       # Compose
kubectl logs -n fcg deploy/kong | grep upstream  # k8s
```

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

**1. Cluster**

```bash
minikube start
```

**2. Build + carga das 4 imagens no cluster local** (ajuste os caminhos se renomeou as pastas apos o clone)

```bash
docker build -t fcg/users-api:1.0 ../FIAPCloudGames-fase3-UsersAPI -f ../FIAPCloudGames-fase3-UsersAPI/src/FCG.API/Dockerfile
minikube image load fcg/users-api:1.0
docker build -t fcg/catalog-api:1.0 ../FIAPCloudGames-fase3-CatalogAPI -f ../FIAPCloudGames-fase3-CatalogAPI/src/CatalogAPI.API/Dockerfile
minikube image load fcg/catalog-api:1.0
docker build -t fcg/payments-api:1.0 ../FIAPCloudGames-fase3-PaymentsAPI -f ../FIAPCloudGames-fase3-PaymentsAPI/src/FCG.API/Dockerfile
minikube image load fcg/payments-api:1.0
docker build -t fcg/notifications-api:1.0 ../FIAPCloudGames-fase3-NotificationsAPI/NotificationsAPI -f ../FIAPCloudGames-fase3-NotificationsAPI/NotificationsAPI/src/Notifications.API/Dockerfile
minikube image load fcg/notifications-api:1.0
```

> O Kong nao entra aqui: ele usa a imagem oficial `kong:3.9`, baixada do Docker Hub pelo proprio cluster.

**3. Regerar o ConfigMap do gateway** (so e obrigatorio se voce editou `kong/kong.yml`; o arquivo gerado esta versionado)

```bash
bash scripts/kong/sync-configmap.sh    # o mesmo que `make kong-config`
```

**4. Aplicar os manifestos** (a numeracao dos arquivos garante a ordem)

```bash
kubectl apply -f k8s/

# Se o ConfigMap do Kong mudou no passo 3, force o rollout:
# o Kong le a config declarativa uma vez, no startup.
kubectl rollout restart deployment/kong -n fcg
```

**5. Verificar**

```bash
kubectl get pods -n fcg
kubectl get deployments,services,configmaps,secrets -n fcg
kubectl rollout status deployment/kong -n fcg
```

**6. Onde fazer as requisicoes**

Nada no cluster e alcancavel do seu terminal por padrao: os Services sao `ClusterIP`, ou seja, so existem dentro do cluster. Voce precisa escolher **uma** das duas pontes abaixo.

**Opcao A -- `port-forward` no gateway (mais rapido; e o que responde a pergunta "onde chamo o Kong?")**

Em um terminal separado, deixe rodando:

```bash
kubectl port-forward service/kong-proxy 8000:8000 -n fcg
```

Enquanto ele estiver de pe, **o gateway atende em `http://localhost:8000`** -- exatamente a mesma URL do Docker Compose:

```bash
GATEWAY=http://localhost:8000

# cadastro e login (rotas anonimas no gateway)
curl -s -X POST $GATEWAY/users/api/users/register -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@fcg.com","password":"Senha123!"}'

TOKEN=$(curl -s -X POST $GATEWAY/users/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"teste@fcg.com","password":"Senha123!"}' | jq -r .accessToken)

# rota protegida: o Kong valida o JWT antes de encaminhar
curl -i $GATEWAY/catalog/api/v1/games -H "Authorization: Bearer $TOKEN"

# sem token o gateway barra (401), sem nem encostar no servico
curl -i $GATEWAY/catalog/api/v1/games
```

**Opcao B -- Ingress**, se voce quiser as URLs com hostname (`http://gateway.fcg.local`, sem porta): ver [Expor as APIs com Ingress](#expor-as-apis-com-ingress-alternativa-ao-port-forward). Exige `minikube tunnel` e uma entrada no arquivo de hosts.

Para debug, o `port-forward` tambem serve para bater direto em um servico, **desviando do gateway** (sem JWT do Kong, sem rate-limit):

```bash
kubectl port-forward service/users-api 8081:8080 -n fcg     # http://localhost:8081/api/auth/login
kubectl port-forward service/catalog-api 8082:8080 -n fcg   # http://localhost:8082/api/v1/games
kubectl port-forward service/kong-proxy 8100:8100 -n fcg    # http://localhost:8100/status/ready e /metrics
```

> Cada `port-forward` ocupa um terminal e cuida de **um** Service. E normal ter dois ou tres abertos ao mesmo tempo (um por porta local).

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
127.0.0.1 gateway.fcg.local
127.0.0.1 users.fcg.local
127.0.0.1 catalog.fcg.local
127.0.0.1 payments.fcg.local
127.0.0.1 notifications.fcg.local
127.0.0.1 rabbitmq.fcg.local
```

Agora cada API responde no seu hostname, na porta 80 (sem porta na URL). São **duas portas de entrada diferentes**, e é importante não confundir:

| Hostname | O que é | Rotas |
|---|---|---|
| `gateway.fcg.local` | **o API Gateway (Kong)** -- caminho oficial | `/users/...`, `/catalog/...` (com prefixo) |
| `users.fcg.local`, `catalog.fcg.local`, ... | atalho direto pro Service, **desviando do gateway** | rotas originais, sem prefixo |

Pelo gateway (com JWT, rate-limit e correlation-id):

```bash
GATEWAY=http://gateway.fcg.local

TOKEN=$(curl -s -X POST $GATEWAY/users/api/auth/login -H "Content-Type: application/json" \
  -d '{"email":"ingress@teste.com","password":"Senha123!"}' | jq -r .accessToken)

curl $GATEWAY/catalog/api/v1/games -H "Authorization: Bearer $TOKEN"
```

Direto no serviço (útil para debug -- repare que **não** tem o prefixo `/users`):

```bash
curl -X POST http://users.fcg.local/api/users/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste Ingress","email":"ingress@teste.com","password":"Senha123!"}'

curl http://catalog.fcg.local/api/v1/games
```

O painel de gestão do RabbitMQ também sai pelo mesmo túnel, em `http://rabbitmq.fcg.local` (login `fcg` / `fcg123`).

> **Por que por hostname e não por caminho (`/users`, `/catalog`)?** Cada API já tem seus próprios prefixos de rota (`/api/users/...`, `/api/v1/games`, etc.), diferentes entre si. Rotear por path exigiria reescrever a URL antes de repassar pro serviço (`rewrite-target`), o que complica sem necessidade aqui. Rotear por hostname mantém as rotas originais intactas — cada domínio aponta pra um Service só.
>
> Esse roteamento por path é justamente o que o **Kong** faz em `gateway.fcg.local/catalog/...`: o `strip_path` da rota remove o prefixo antes de repassar. O Ingress continua sendo só a porta de entrada do cluster — quem decide rota, autentica e aplica rate-limit é o gateway.

## Troubleshooting

### `401 {"message":"No mandatory 'iss' in claims"}` chamando o gateway

O token que voce mandou nao tem a claim `iss`, e o plugin `jwt` do Kong precisa dela para saber **qual credencial** usar. Quase sempre a causa nao esta no Kong nem no codigo, e sim no **pod rodando um build antigo do `users-api`**, anterior a claim existir.

Confirme comparando a imagem do host com a que esta dentro do cluster:

```bash
docker images --no-trunc --format '{{.ID}}' fcg/users-api:1.0
minikube ssh -- "docker images --no-trunc --format '{{.ID}}' fcg/users-api:1.0"
```

Se os IDs divergirem, o cluster esta com codigo velho. E se quiser a prova direta:

```bash
# a imagem que o pod REALMENTE roda tem a key Issuer?
minikube ssh -- "docker run --rm --entrypoint cat fcg/users-api:1.0 /app/appsettings.json" | grep -A4 JwtSettings

# e as claims de um token de verdade
echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq .iss    # esperado: "FCG"
```

Correcao: `make k8s-build` (o script detecta a divergencia, troca a imagem e sobe os pods de novo).

> **Por que isso acontece:** `minikube image load fcg/users-api:1.0` **nao sobrescreve** uma tag que ja existe no cluster quando um container esta usando aquela imagem -- e termina com **codigo de sucesso**, sem aviso. Somado ao `imagePullPolicy: IfNotPresent` e a uma tag fixa (`:1.0`), o `kubectl apply` tambem nao muda o pod spec, entao nao ha rollout: o cluster fica rodando codigo antigo indefinidamente enquanto tudo aparenta ter funcionado.
>
> O `scripts/k8s/build-images.sh` cobre isso: compara o ID da imagem no host com o do cluster e, quando divergem, escala o Deployment para 0 (a tag so pode ser trocada quando nenhum container a usa), troca a imagem e volta as replicas. No fim ele reconfere os quatro servicos e **falha** se algum ficou defasado.

### `make k8s-build` avisa `[skip] Dockerfile nao encontrado`

O repo daquele servico foi reestruturado e nao tem mais o Dockerfile no caminho esperado. O script segue com os outros servicos e o cluster continua com a imagem de um build anterior -- o que roda, mas com codigo velho. Ajuste o caminho em `scripts/k8s/build-images.sh` (e no `docker-compose.yml`) quando o repo definir o novo layout.

> Hoje isso acontece com o **notifications-api**: o repo migrou de PostgreSQL para DynamoDB e nao expoe mais o projeto `Notifications.API` nem um Dockerfile.

### `401 {"message":"Unauthorized"}` numa rota que deveria ser anonima

Confira o **metodo**. As rotas de login e register sao liberadas so para `POST`/`OPTIONS`; qualquer outro verbo cai na catch-all `/users`, que exige JWT. Ver [Rotas expostas](#rotas-expostas).

### `401 No credentials found for given 'iss'`

O token tem `iss`, mas com valor diferente do que o gateway espera. Os dois lados leem a mesma variavel `JWT_ISSUER` -- reinicie **os dois** apos mudar (ver [Autenticacao: quem emite e quem valida](#autenticacao-quem-emite-e-quem-valida)).

### Editei `kong/kong.yml` e nada mudou

O Kong le a config declarativa uma vez, no startup. Rode `make k8s-deploy` (que propaga o hash e rola o gateway) ou `kubectl rollout restart deployment/kong -n fcg`.

## Variaveis de ambiente por servico

| Variavel | users | catalog | payments | notifications | Origem |
|---|:---:|:---:|:---:|:---:|---|
| `ConnectionStrings__DefaultConnection` | Sim | Sim | Sim | Sim | Secret |
| `ConnectionStrings__RabbitMqConnection` | — | Sim | — | — | Secret |
| `RabbitMq__Host` | Sim | — | Sim | Sim | ConfigMap |
| `RabbitMq__Password` | Sim | — | Sim | Sim | Secret |
| `JwtSettings__SecretKey` | Sim | Sim | — | — | Secret |
| `ASPNETCORE_ENVIRONMENT` | Sim | Sim | Sim | Sim | ConfigMap |

O gateway consome duas variaveis proprias:

| Variavel | Origem (k8s) | Origem (Compose) | Para que |
|---|---|---|---|
| `JWT_SECRET_KEY` | Secret `fcg-secrets` (`JwtSettings__SecretKey`) | `.env` | chave HMAC para validar a assinatura do token |
| `JWT_ISSUER` | ConfigMap `fcg-config` | `.env` (default `FCG`) | claim `iss` esperada nos tokens; o users-api le a mesma variavel em `JwtSettings__Issuer` |

As demais variaveis do Kong (`KONG_*`) sao fixas no manifesto/Compose e nao dependem de ConfigMap nem Secret. As que valem conhecer: `KONG_ADMIN_LISTEN` (Admin API no loopback do pod), `KONG_TRUSTED_IPS`/`KONG_REAL_IP_HEADER`/`KONG_REAL_IP_RECURSIVE` (IP real do cliente atras do Ingress, para o rate-limit por IP) e `KONG_HEADERS=latency_tokens` (mantem os headers de latencia, tira o `Server: kong/<versao>`).

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
