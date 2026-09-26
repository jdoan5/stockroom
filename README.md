# Stockroom

A small internal inventory app: SQL Server, ASP.NET Core MVC, jQuery, and a
Power BI report — built on the inventory schema from
[Databases-and-Data-Platforms](https://github.com/jdoan5/Databases-and-Data-Platforms),
ported from PostgreSQL to T-SQL.

## Stages

| # | Stage | Status |
|---|---|---|
| 1 | SQL Server database — schema, seed, views, triggers, stored procedures | ✅ done |
| 2 | ASP.NET Core MVC pages — dashboard, stock, low stock, purchase orders | ✅ done |
| 3 | jQuery forms — transfer stock, receive a purchase order | ✅ done |
| 4 | Power BI report on the reporting views | |

## Run it

Needs Docker. On Apple Silicon, SQL Server runs under Rosetta (there is no arm64 image).

```bash
make env      # creates .env with a random SA password
              # then set ACCEPT_EULA=Y in .env if you accept the SQL Server license
make up       # start SQL Server
make db       # create the database and run db/01..05
make verify   # run the checks
make run      # web app at http://localhost:5271
```

The web app is ASP.NET Core MVC (.NET 10) — controllers and Razor views — reading
the database through [Dapper](https://github.com/DapperLib/Dapper). All queries go
through the reporting views in `db/03_views.sql`, parameterised, and run unchanged
in DataGrip. The connection string comes from `.env` via `make run`; no password is
stored in `appsettings.json`.

The write paths are jQuery over AJAX: **Transfer stock** validates in the browser
(jQuery unobtrusive validation, driven by the C# data annotations), posts to the
`transfer_stock` procedure, and live-reloads the product's stock panel; **Receive**
on the purchase orders page calls `receive_purchase_order` and reloads just the
table. Errors the procedures `THROW` (50001–50011) are mapped to the form field
they belong to, so "Insufficient stock at WH-WEST: have 235, need 9999" appears
under Quantity. Both endpoints require an anti-forgery token.

Connect from DataGrip: `localhost:1433`, database `Stockroom`, user `sa`, password from `.env`.

## Porting notes: PostgreSQL → SQL Server

The changes that affect behaviour, not just syntax:

- **Triggers fire once per statement**, not once per row. All affected rows arrive
  together in `inserted`, so the triggers are set-based. A row-at-a-time port
  silently updates only one row of a multi-row insert — swap one in and
  `make verify` shows a received PO whose second line never reached stock:
  `stapler 12->12, RECEIVED`.
- **Procedures aren't automatically atomic.** A Postgres function runs in one
  transaction; a SQL Server procedure autocommits each statement unless told
  otherwise. Both procedures use `SET XACT_ABORT ON` and an explicit transaction.
- **`TIMESTAMP` is not a date** in SQL Server — it's `rowversion`. Dates are `DATETIME2`.
- **No `ENUM`** — replaced with `CHECK` constraints.
- **No `BEFORE` triggers** — `last_updated` is maintained by an `AFTER UPDATE` trigger.
- **A self-referencing foreign key can't cascade**, so `categories.parent_id` has no `ON DELETE`.

Two bugs from the original schema are fixed here: a negative stock adjustment
(shrinkage) can now be recorded, and shipping stock that isn't there now fails
instead of silently leaving a balance of zero.

## License

MIT
