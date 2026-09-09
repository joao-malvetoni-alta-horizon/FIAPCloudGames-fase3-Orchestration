# Observabilidade

## Objetivo

A solução utiliza New Relic para monitoramento dos microsserviços.

## Serviços monitorados

- FIAPCloudGames-fase3-UsersAPI
- FIAPCloudGames-fase3-CatalogAPI
- FIAPCloudGames-fase3-PaymentsAPI
- FIAPCloudGames-fase3-NotificationsAPI

## APM

O New Relic .NET Agent é utilizado para instrumentação automática
das aplicações ASP.NET Core.

## Métricas

São coletadas métricas relacionadas a:

- throughput;
- tempo de resposta;
- erros;
- transações;
- desempenho das aplicações.

## Logs

Os logs das aplicações são encaminhados ao New Relic,
permitindo análise em conjunto com os traces.

## Distributed Tracing

O distributed tracing permite acompanhar o fluxo de compra
entre CatalogAPI, RabbitMQ e PaymentsAPI.

## Configuração

A chave de licença é fornecida através da variável:

NEW_RELIC_LICENSE_KEY

A chave não é armazenada no código-fonte.

## Validação

Para validar a solução:

1. iniciar os serviços;
2. executar uma consulta no CatalogAPI;
3. executar uma compra;
4. verificar APM;
5. verificar logs;
6. verificar traces;
7. verificar o trace distribuído entre CatalogAPI e PaymentsAPI.