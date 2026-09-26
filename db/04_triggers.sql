-- 04_triggers.sql — keep stock_levels and PO status in step with the ledger.
--
-- Key difference from Postgres: SQL Server triggers fire ONCE PER STATEMENT,
-- with all affected rows in `inserted`. So every trigger here is set-based;
-- a row-at-a-time port would silently handle only one row of a multi-row insert.

-- 1. New ledger rows -> adjust stock_levels
CREATE OR ALTER TRIGGER dbo.trg_stock_movements_apply
ON dbo.stock_movements AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Make sure a balance row exists for each (product, warehouse) touched.
    INSERT INTO dbo.stock_levels (product_id, warehouse_id, quantity)
    SELECT DISTINCT i.product_id, i.warehouse_id, 0
    FROM inserted i
    WHERE NOT EXISTS (SELECT 1 FROM dbo.stock_levels sl WITH (UPDLOCK, HOLDLOCK)
                      WHERE sl.product_id = i.product_id AND sl.warehouse_id = i.warehouse_id);

    -- Apply the net change per (product, warehouse). If stock would go negative,
    -- ck_stock_levels_quantity fails and the whole insert rolls back.
    UPDATE sl
       SET quantity = sl.quantity + d.delta
    FROM dbo.stock_levels sl
    JOIN (SELECT product_id, warehouse_id,
                 SUM(CASE WHEN movement_type IN ('OUT','TRANSFER_OUT')
                          THEN -quantity ELSE quantity END) AS delta
          FROM inserted
          GROUP BY product_id, warehouse_id) d
      ON d.product_id = sl.product_id AND d.warehouse_id = sl.warehouse_id;
END;
GO

-- 2. Keep last_updated current. (SQL Server has no BEFORE triggers, so this is AFTER UPDATE.)
CREATE OR ALTER TRIGGER dbo.trg_stock_levels_touch
ON dbo.stock_levels AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(quantity) RETURN;   -- also stops this trigger re-firing itself

    UPDATE sl SET last_updated = SYSUTCDATETIME()
    FROM dbo.stock_levels sl
    JOIN inserted i ON i.product_id = sl.product_id AND i.warehouse_id = sl.warehouse_id;
END;
GO

-- 3. Line receipts change -> roll the PO status forward
CREATE OR ALTER TRIGGER dbo.trg_poi_update_po_status
ON dbo.purchase_order_items AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(quantity_received) RETURN;

    UPDATE po
       SET status = t.new_status,
           received_date = CASE WHEN t.new_status = 'RECEIVED' AND po.received_date IS NULL
                                THEN CAST(SYSUTCDATETIME() AS DATE) ELSE po.received_date END
    FROM dbo.purchase_orders po
    JOIN (SELECT po_id,
                 CASE WHEN SUM(quantity_received) = 0                     THEN 'PLACED'
                      WHEN SUM(quantity_received) < SUM(quantity_ordered) THEN 'PARTIALLY_RECEIVED'
                      ELSE 'RECEIVED' END AS new_status
          FROM dbo.purchase_order_items
          WHERE po_id IN (SELECT po_id FROM inserted)
          GROUP BY po_id) t
      ON t.po_id = po.po_id
    WHERE po.status NOT IN ('DRAFT', 'CANCELLED');
END;
GO
