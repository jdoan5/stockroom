# Stockroom

A small internal inventory app: SQL Server, ASP.NET Core MVC, jQuery, and a
Power BI report — built on the inventory schema from
[Databases-and-Data-Platforms](https://github.com/jdoan5/Databases-and-Data-Platforms),
ported from PostgreSQL to T-SQL.

## Stages

| # | Stage | Status |
|---|---|---|
| 1 | SQL Server database — schema, seed, views, triggers, stored procedures | ✅ done |
| 2 | ASP.NET Core MVC pages — stock, low stock, purchase orders | |
| 3 | jQuery forms — transfer stock, receive a purchase order | |
| 4 | Power BI report on the reporting views | |

## Run it

Needs Docker. On Apple Silicon, SQL Server runs under Rosetta (there is no arm64 image).

```bash
make env      # creates .env with a random SA password
              # then set ACCEPT_EULA=Y in .env if you accept the SQL Server license
make up       # start SQL Server
make db       # create the database and run db/01..05
make verify   # run the checks
```

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
