-include .env
export

SQLCMD = docker exec -i stockroom-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -C -b

.PHONY: env up db verify down reset

env:     ## create .env with a random SA password (you still set ACCEPT_EULA)
	@test -f .env || { cp .env.example .env; pw=$$(openssl rand -base64 18 | tr -d "/+=")Aa1!; sed -i "" "s|^MSSQL_SA_PASSWORD=.*|MSSQL_SA_PASSWORD=$$pw|" .env; echo "created .env"; }

up:      ## start SQL Server and wait until it answers
	docker compose up -d
	@until $(SQLCMD) -Q "SELECT 1" >/dev/null 2>&1; do sleep 2; done; echo "SQL Server ready"

db:      ## create the Stockroom database and run the scripts in order
	$(SQLCMD) -Q "IF DB_ID(N'Stockroom') IS NULL CREATE DATABASE Stockroom"
	@for f in 01_schema 02_seed 03_views 04_triggers 05_procedures; do echo "-> $$f"; $(SQLCMD) -d Stockroom -i /db/$$f.sql || exit 1; done

verify:  ## run the checks
	$(SQLCMD) -d Stockroom -i /db/90_verify.sql

reset: db verify  ## rebuild from scratch and check

down:    ## stop SQL Server (data is kept in a volume)
	docker compose down
