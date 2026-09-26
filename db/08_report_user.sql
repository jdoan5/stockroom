-- 08_report_user.sql — the read-only database user Power BI connects as.
--
-- It can SELECT from the rpt views (06_reporting.sql) and nothing else: no
-- dbo tables, no dbo views, no procedures, no writes. The views still return
-- data because they and the tables all belong to dbo — the same ownership
-- chaining that lets the app's procedures write (see 07_app_user.sql). And in
-- Power BI's Navigator this user sees only the six rpt views.
--
-- A contained user (a password stored in this database, no server login),
-- which is what Azure SQL Database expects. Run via `make azure-report-user`,
-- which passes REPORT_USER and REPORT_PASSWORD in from .env.

IF DATABASE_PRINCIPAL_ID(N'$(REPORT_USER)') IS NULL
    CREATE USER [$(REPORT_USER)] WITH PASSWORD = N'$(REPORT_PASSWORD)';
ELSE
    ALTER USER [$(REPORT_USER)] WITH PASSWORD = N'$(REPORT_PASSWORD)';

GRANT SELECT ON SCHEMA::rpt TO [$(REPORT_USER)];
GO
