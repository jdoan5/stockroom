-- 06_reporting.sql — star-schema views for the Power BI report (schema rpt).
--
-- The dbo views in 03_views.sql are shaped for the web pages: pre-aggregated,
-- joined on codes, and v_recent_movements only covers the last 30 days. These
-- are shaped for a Power BI model instead: one view per dimension or fact,
-- integer keys that join one-to-many, one row per balance / movement / PO line,
-- and nothing pre-aggregated, so the model can slice every number any way.
--
--   rpt.dim_product    one row per product (category and subcategory flattened in)
--   rpt.dim_warehouse  one row per warehouse
--   rpt.dim_supplier   one row per supplier (no contact details: the report doesn't need them)
--   rpt.fact_stock     one row per product x warehouse — the current balance
--   rpt.fact_movement  one row per ledger entry in stock_movements
--   rpt.fact_po_line   one row per purchase order line
--
-- Power BI connects as a user that can read this schema and nothing else
-- (08_report_user.sql). The views belong to dbo, like the tables, so ownership
-- chaining lets them read tables that user has no permission on.
--
-- Not WITH SCHEMABINDING, on purpose: 01_schema.sql drops and recreates the
-- tables, which a schema-bound view would block. Safe to re-run.

SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'rpt') IS NULL
    EXEC (N'CREATE SCHEMA rpt AUTHORIZATION dbo');   -- CREATE SCHEMA must be alone in its batch
GO

-- ----------------------------------------------------------------------------
-- Dimensions
-- ----------------------------------------------------------------------------

-- Categories are two levels deep (Electronics > Laptops). A product filed
-- directly under a top-level category repeats it as its subcategory, so a
-- Category > Subcategory hierarchy in Power BI has no blank level.
CREATE OR ALTER VIEW rpt.dim_product AS
SELECT p.product_id,
       p.sku,
       p.name                                          AS product_name,
       COALESCE(parent.name, c.name, N'Uncategorized') AS category,
       COALESCE(c.name, N'Uncategorized')              AS subcategory,
       p.unit_cost,
       p.unit_price,
       p.is_active
FROM dbo.products p
LEFT JOIN dbo.categories c      ON c.category_id      = p.category_id
LEFT JOIN dbo.categories parent ON parent.category_id = c.parent_id;
GO

CREATE OR ALTER VIEW rpt.dim_warehouse AS
SELECT warehouse_id,
       code AS warehouse_code,
       name AS warehouse_name,
       city,
       country,
       is_active
FROM dbo.warehouses;
GO

CREATE OR ALTER VIEW rpt.dim_supplier AS
SELECT supplier_id,
       name AS supplier_name,
       city,
       country,
       is_active
FROM dbo.suppliers;
GO

-- ----------------------------------------------------------------------------
-- Facts
-- ----------------------------------------------------------------------------

-- Current balance per product x warehouse. "Low" is the same rule as
-- v_low_stock_items (quantity below the reorder point), so the report and the
-- web app's Low stock page always agree.
CREATE OR ALTER VIEW rpt.fact_stock AS
SELECT sl.product_id,
       sl.warehouse_id,
       sl.quantity,
       p.reorder_point,
       CAST(CASE WHEN sl.quantity < p.reorder_point THEN 1 ELSE 0 END AS BIT) AS is_low_stock,
       CASE WHEN sl.quantity < p.reorder_point AND sl.quantity = 0 THEN 'Out of stock'
            WHEN sl.quantity < p.reorder_point                     THEN 'Low'
            ELSE 'OK' END                                                     AS stock_status,
       CASE WHEN sl.quantity < p.reorder_point AND sl.quantity = 0 THEN 1
            WHEN sl.quantity < p.reorder_point                     THEN 2
            ELSE 3 END                                                        AS stock_status_sort,
       CASE WHEN sl.quantity < p.reorder_point
            THEN p.reorder_point - sl.quantity ELSE 0 END                     AS units_below_reorder,
       -- same formula as v_low_stock_items.suggested_order_qty, 0 when not low
       CASE WHEN sl.quantity >= p.reorder_point                    THEN 0
            WHEN p.reorder_quantity > p.reorder_point - sl.quantity THEN p.reorder_quantity
            ELSE p.reorder_point - sl.quantity END                            AS suggested_order_qty,
       sl.quantity * p.unit_cost                                              AS value_at_cost,
       sl.quantity * p.unit_price                                             AS value_at_retail
FROM dbo.stock_levels sl
JOIN dbo.products p ON p.product_id = sl.product_id;
GO

-- One row per ledger entry. signed_quantity uses the same rule as
-- trg_stock_movements_apply: OUT and TRANSFER_OUT subtract, everything else
-- adds (an ADJUSTMENT carries its own sign). Transfers therefore net to zero
-- across warehouses but show up per warehouse.
-- The ledger doesn't record the cost at the time of the movement, so value
-- uses today's unit cost.
CREATE OR ALTER VIEW rpt.fact_movement AS
SELECT m.movement_id,
       CAST(m.created_at AS DATE) AS movement_date,      -- joins to the model's Date table
       m.created_at               AS movement_time_utc,
       m.product_id,
       m.warehouse_id,
       m.movement_type,
       s.signed_quantity,
       CASE WHEN s.signed_quantity > 0 THEN  s.signed_quantity ELSE 0 END AS units_in,
       CASE WHEN s.signed_quantity < 0 THEN -s.signed_quantity ELSE 0 END AS units_out,
       s.signed_quantity * p.unit_cost                                    AS value_at_cost,
       m.reference_type,
       m.reference_id,
       m.notes
FROM dbo.stock_movements m
JOIN dbo.products p ON p.product_id = m.product_id
CROSS APPLY (SELECT CASE WHEN m.movement_type IN ('OUT', 'TRANSFER_OUT')
                         THEN -m.quantity ELSE m.quantity END AS signed_quantity) s;
GO

-- One row per purchase order line, with the order's header fields repeated.
-- "Open" means placed but not fully received; a DRAFT was never sent and a
-- CANCELLED order won't arrive, so neither counts as open.
-- is_overdue compares with today's date (UTC) when the view is queried, i.e.
-- when the Power BI model is refreshed.
CREATE OR ALTER VIEW rpt.fact_po_line AS
SELECT i.po_item_id,
       o.po_id,
       o.po_number,
       o.supplier_id,
       o.warehouse_id,
       i.product_id,
       o.status AS po_status,
       CASE o.status WHEN 'DRAFT'              THEN 1
                     WHEN 'PLACED'             THEN 2
                     WHEN 'PARTIALLY_RECEIVED' THEN 3
                     WHEN 'RECEIVED'           THEN 4
                     ELSE 5 END AS po_status_sort,                -- CANCELLED
       o.order_date,
       o.expected_date,
       o.received_date,
       DATEDIFF(DAY, o.order_date, o.received_date) AS lead_time_days,   -- NULL until received
       i.quantity_ordered,
       i.quantity_received,
       x.is_open * (i.quantity_ordered - i.quantity_received)               AS quantity_open,
       i.unit_cost,
       i.quantity_ordered  * i.unit_cost                                    AS ordered_value,
       i.quantity_received * i.unit_cost                                    AS received_value,
       x.is_open * (i.quantity_ordered - i.quantity_received) * i.unit_cost AS open_value,
       CAST(x.is_open AS BIT)                                               AS is_open,
       CAST(CASE WHEN x.is_open = 1 AND o.expected_date < CAST(SYSUTCDATETIME() AS DATE)
                 THEN 1 ELSE 0 END AS BIT)                                  AS is_overdue
FROM dbo.purchase_order_items i
JOIN dbo.purchase_orders o ON o.po_id = i.po_id
CROSS APPLY (SELECT CASE WHEN o.status IN ('PLACED', 'PARTIALLY_RECEIVED')
                         THEN 1 ELSE 0 END AS is_open) x;
GO
