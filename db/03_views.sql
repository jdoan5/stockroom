-- 03_views.sql — reporting views (also the source for the Power BI report).

CREATE OR ALTER VIEW dbo.v_current_stock AS
SELECT p.product_id, p.sku, p.name AS product_name, c.name AS category,
       w.warehouse_id, w.code AS warehouse_code, w.name AS warehouse_name,
       sl.quantity, p.reorder_point, p.reorder_quantity, sl.last_updated
FROM dbo.stock_levels sl
JOIN dbo.products   p ON p.product_id   = sl.product_id
JOIN dbo.warehouses w ON w.warehouse_id = sl.warehouse_id
LEFT JOIN dbo.categories c ON c.category_id = p.category_id;
GO

CREATE OR ALTER VIEW dbo.v_low_stock_items AS
SELECT sku, product_name, warehouse_code, quantity, reorder_point, reorder_quantity,
       reorder_point - quantity AS deficit,
       -- CASE instead of GREATEST(), which only exists from SQL Server 2022
       CASE WHEN reorder_quantity > reorder_point - quantity
            THEN reorder_quantity ELSE reorder_point - quantity END AS suggested_order_qty
FROM dbo.v_current_stock
WHERE quantity < reorder_point;
GO

CREATE OR ALTER VIEW dbo.v_purchase_order_summary AS
SELECT po.po_id, po.po_number, s.name AS supplier_name, w.code AS warehouse_code,
       po.status, po.order_date, po.expected_date, po.received_date,
       COUNT(poi.po_item_id)                     AS line_count,
       SUM(poi.quantity_ordered)                 AS total_ordered,
       SUM(poi.quantity_received)                AS total_received,
       SUM(poi.quantity_ordered * poi.unit_cost) AS total_value
FROM dbo.purchase_orders po
JOIN dbo.suppliers  s ON s.supplier_id  = po.supplier_id
JOIN dbo.warehouses w ON w.warehouse_id = po.warehouse_id
LEFT JOIN dbo.purchase_order_items poi ON poi.po_id = po.po_id
GROUP BY po.po_id, po.po_number, s.name, w.code,
         po.status, po.order_date, po.expected_date, po.received_date;
GO

CREATE OR ALTER VIEW dbo.v_stock_valuation AS
SELECT w.warehouse_id, w.code AS warehouse_code, w.name AS warehouse_name,
       COUNT(DISTINCT sl.product_id)  AS distinct_skus,
       SUM(sl.quantity)               AS total_units,
       SUM(sl.quantity * p.unit_cost)  AS valuation_at_cost,
       SUM(sl.quantity * p.unit_price) AS valuation_at_retail
FROM dbo.warehouses w
LEFT JOIN dbo.stock_levels sl ON sl.warehouse_id = w.warehouse_id
LEFT JOIN dbo.products     p  ON p.product_id    = sl.product_id
GROUP BY w.warehouse_id, w.code, w.name;
GO

CREATE OR ALTER VIEW dbo.v_recent_movements AS
SELECT sm.movement_id, sm.created_at, p.sku, p.name AS product_name,
       w.code AS warehouse_code, sm.movement_type, sm.quantity,
       sm.reference_type, sm.reference_id, sm.notes
FROM dbo.stock_movements sm
JOIN dbo.products   p ON p.product_id   = sm.product_id
JOIN dbo.warehouses w ON w.warehouse_id = sm.warehouse_id
WHERE sm.created_at >= DATEADD(DAY, -30, CAST(SYSUTCDATETIME() AS DATE));
GO
