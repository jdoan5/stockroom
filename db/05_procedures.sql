-- 05_procedures.sql — the two write operations the app will call.
--
-- Key difference from Postgres: a Postgres function runs in one transaction
-- automatically; a SQL Server procedure does not. XACT_ABORT + an explicit
-- transaction make each procedure all-or-nothing.

CREATE OR ALTER PROCEDURE dbo.transfer_stock
    @sku VARCHAR(40), @from_code VARCHAR(10), @to_code VARCHAR(10), @qty INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @product_id INT, @from_wh INT, @to_wh INT, @available INT, @msg NVARCHAR(400);

    SELECT @product_id = product_id FROM dbo.products   WHERE sku  = @sku;
    SELECT @from_wh    = warehouse_id FROM dbo.warehouses WHERE code = @from_code;
    SELECT @to_wh      = warehouse_id FROM dbo.warehouses WHERE code = @to_code;

    IF @qty IS NULL OR @qty <= 0  THROW 50001, N'Quantity must be positive.', 1;
    IF @product_id IS NULL        THROW 50002, N'Unknown SKU.', 1;
    IF @from_wh IS NULL OR @to_wh IS NULL THROW 50003, N'Unknown warehouse.', 1;
    IF @from_wh = @to_wh          THROW 50004, N'Source and destination are the same.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @available = quantity
        FROM dbo.stock_levels WITH (UPDLOCK, HOLDLOCK)   -- hold it so a concurrent transfer waits
        WHERE product_id = @product_id AND warehouse_id = @from_wh;

        IF COALESCE(@available, 0) < @qty
        BEGIN
            SET @msg = CONCAT(N'Insufficient stock at ', @from_code, N': have ',
                              COALESCE(@available, 0), N', need ', @qty, N'.');
            THROW 50005, @msg, 1;
        END;

        INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity, reference_type, notes)
        VALUES (@product_id, @from_wh, 'TRANSFER_OUT', @qty, 'TRANSFER', CONCAT(N'To ', @to_code)),
               (@product_id, @to_wh,   'TRANSFER_IN',  @qty, 'TRANSFER', CONCAT(N'From ', @from_code));

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;

    SELECT CONCAT(N'Transferred ', @qty, N' x ', @sku, N' from ', @from_code, N' to ', @to_code, N'.') AS message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.receive_purchase_order
    @po_number VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @po_id INT, @warehouse_id INT, @lines INT, @units INT, @status VARCHAR(20);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @po_id = po_id, @warehouse_id = warehouse_id, @status = status
        FROM dbo.purchase_orders WITH (UPDLOCK) WHERE po_number = @po_number;

        IF @po_id IS NULL THROW 50010, N'Unknown purchase order.', 1;
        -- A DRAFT or CANCELLED order was never placed, so nothing should arrive for it.
        IF @status IN ('DRAFT', 'CANCELLED') THROW 50011, N'Only placed orders can be received.', 1;

        SELECT @lines = COUNT(*), @units = COALESCE(SUM(quantity_ordered - quantity_received), 0)
        FROM dbo.purchase_order_items
        WHERE po_id = @po_id AND quantity_received < quantity_ordered;

        -- Set-based: one statement for all lines (the Postgres version looped).
        INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity, reference_type, reference_id, notes)
        SELECT product_id, @warehouse_id, 'IN', quantity_ordered - quantity_received,
               'PURCHASE_ORDER', @po_id, CONCAT(N'Receipt of ', @po_number)
        FROM dbo.purchase_order_items
        WHERE po_id = @po_id AND quantity_received < quantity_ordered;

        UPDATE dbo.purchase_order_items
           SET quantity_received = quantity_ordered
        WHERE po_id = @po_id AND quantity_received < quantity_ordered;

        SELECT @status = status FROM dbo.purchase_orders WHERE po_id = @po_id;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;

    SELECT CONCAT(N'Received ', @po_number, N': ', @lines, N' line(s), ',
                  @units, N' unit(s). Status: ', @status, N'.') AS message;
END;
GO
