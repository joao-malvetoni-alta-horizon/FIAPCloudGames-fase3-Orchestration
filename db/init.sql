-- Cria os bancos de catalog, notifications e payments na primeira subida do Postgres.
-- O banco 'fcgdb' (users) ja nasce via POSTGRES_DB no docker-compose.
CREATE DATABASE catalogdb;
CREATE DATABASE notificationsdb;
CREATE DATABASE paymentsdb;
