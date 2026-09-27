-- 07_app_user.sql — the database user the web app connects as in Azure.
--
-- Least privilege: it can read, and it can run the four procedures in
-- 05_procedures.sql, but it cannot INSERT, UPDATE or DELETE any table directly.
-- Every change has to go through transfer_stock, receive_purchase_order,
-- add_product or adjust_stock, so their rules (enough stock, unique SKUs,
-- all-or-nothing) can't be bypassed even with the app's own password.
--
-- A GRANT is on the procedure itself, so re-run this after adding a procedure
-- (CREATE OR ALTER keeps the grants on the ones that already exist).
--
-- The procedures can still write because they, the tables and the triggers
-- all belong to dbo: SQL Server's ownership chaining skips the permission
-- check inside an object owned by the same owner as the object it touches.
--
-- A contained user (a password stored in this database, no server login),
-- which is what Azure SQL Database expects. Run via `make azure-app-user`,
-- which passes APP_USER and APP_PASSWORD in from .env.

IF DATABASE_PRINCIPAL_ID(N'$(APP_USER)') IS NULL
    CREATE USER [$(APP_USER)] WITH PASSWORD = N'$(APP_PASSWORD)';
ELSE
    ALTER USER [$(APP_USER)] WITH PASSWORD = N'$(APP_PASSWORD)';

GRANT SELECT  ON SCHEMA::dbo                    TO [$(APP_USER)];
GRANT EXECUTE ON OBJECT::dbo.transfer_stock         TO [$(APP_USER)];
GRANT EXECUTE ON OBJECT::dbo.receive_purchase_order TO [$(APP_USER)];
GRANT EXECUTE ON OBJECT::dbo.add_product            TO [$(APP_USER)];
GRANT EXECUTE ON OBJECT::dbo.adjust_stock           TO [$(APP_USER)];
GO
