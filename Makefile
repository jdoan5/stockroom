-include .env
export

SQLCMD = docker exec -i stockroom-db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -C -b

.PHONY: env up db verify down reset run azure-db azure-verify azure-app-user azure-deploy

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

# TrustServerCertificate: the container uses a self-signed certificate. Local dev only.
CONN = Server=localhost,1433;Database=Stockroom;User Id=sa;Password=$$MSSQL_SA_PASSWORD;TrustServerCertificate=True

run:     ## run the web app at http://localhost:5271
	cd src/Stockroom.Web && ConnectionStrings__Stockroom="$(CONN)" dotnet run --launch-profile http

down:    ## stop SQL Server (data is kept in a volume)
	docker compose down

# --- Azure (Stage 4) -----------------------------------------------------------
# Same scripts, run against Azure SQL through the sqlcmd inside the local container.
# Azure has a trusted certificate, so no -C here.
AZSQL = docker exec -i stockroom-db /opt/mssql-tools18/bin/sqlcmd -S tcp:$$AZURE_SQL_SERVER.database.windows.net,1433 -d Stockroom -U $$AZURE_SQL_ADMIN -P "$$AZURE_SQL_ADMIN_PASSWORD" -b -l 60

azure-db:        ## load db/01..05 into Azure SQL (also re-seeds the live demo)
	@for f in 01_schema 02_seed 03_views 04_triggers 05_procedures; do echo "-> $$f"; $(AZSQL) -i /db/$$f.sql || exit 1; done

azure-verify:    ## run the checks against Azure SQL
	$(AZSQL) -i /db/90_verify.sql

azure-app-user:  ## create/refresh the least-privilege user the web app connects as
	$(AZSQL) -v APP_USER="$$AZURE_SQL_APP_USER" APP_PASSWORD="$$AZURE_SQL_APP_PASSWORD" -i /db/07_app_user.sql

# Pins an exact image rather than :latest, so every deploy is a new revision and
# rolling back is one command. image.yml only builds when src/ or the workflow
# changes, so the tag is the last commit that touched those — a README-only
# commit has no image of its own. Push first and let image.yml finish.
IMAGE_SHA = $$(git log -1 --format=%H -- src .github/workflows/image.yml)

azure-deploy:    ## run the latest built image in the Container App
	az containerapp update -n ca-stockroom -g $$AZURE_RESOURCE_GROUP --image ghcr.io/jdoan5/stockroom:$(IMAGE_SHA) --query properties.latestRevisionName -o tsv
