-- 05_procedures.sql — the four write operations the app calls: transfer_stock,
-- receive_purchase_order, add_product and adjust_stock.
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

-- A new product starts with a zero balance in every active warehouse, so it is
-- on the Stock page (at 0) and on Low stock (0 is below its reorder point) like
-- any product nobody has received yet. Zero is what its empty ledger adds up
-- to, so no movement row is written; stock arrives later through the ledger.
CREATE OR ALTER PROCEDURE dbo.add_product
    @sku VARCHAR(40), @name NVARCHAR(200), @category NVARCHAR(100),
    @unit_cost DECIMAL(12,2), @unit_price DECIMAL(12,2), @reorder_point INT, @reorder_quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @category_id INT, @product_id INT, @msg NVARCHAR(400);

    SET @sku  = UPPER(TRIM(@sku));   -- stored upper-case, so elec-aud-001 is ELEC-AUD-001
    SET @name = TRIM(@name);
    SELECT @category_id = category_id FROM dbo.categories WHERE name = @category;

    IF COALESCE(@sku, '') = '' OR COALESCE(@name, N'') = N'' THROW 50022, N'Enter a SKU and a name.', 1;
    IF @category_id IS NULL THROW 50021, N'Unknown category.', 1;
    -- The table CHECKs would stop these too, but with a constraint name instead of a sentence.
    IF @unit_cost IS NULL OR @unit_cost < 0 OR @unit_price IS NULL OR @unit_price < 0
       OR @reorder_point IS NULL OR @reorder_point < 0 OR @reorder_quantity IS NULL OR @reorder_quantity < 1
        THROW 50023, N'Cost, price and reorder point can''t be negative, and the reorder quantity must be at least 1.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- HOLDLOCK locks this SKU's place in the unique index even while no row
        -- is there, and UPDLOCK makes a second add of the same SKU wait on this
        -- line until the first commits; it then finds the row and gets 50020.
        -- (HOLDLOCK alone would let both pass, then deadlock on the INSERT.)
        IF EXISTS (SELECT 1 FROM dbo.products WITH (UPDLOCK, HOLDLOCK) WHERE sku = @sku)
        BEGIN
            SET @msg = CONCAT(N'SKU ', @sku, N' already exists.');
            THROW 50020, @msg, 1;
        END;

        INSERT INTO dbo.products (sku, name, category_id, unit_price, unit_cost, reorder_point, reorder_quantity, is_active)
        VALUES (@sku, @name, @category_id, @unit_price, @unit_cost, @reorder_point, @reorder_quantity, 1);
        SET @product_id = SCOPE_IDENTITY();

        -- Set-based: every warehouse's balance in one statement.
        INSERT INTO dbo.stock_levels (product_id, warehouse_id, quantity)
        SELECT @product_id, warehouse_id, 0
        FROM dbo.warehouses
        WHERE is_active = 1;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;

    SELECT CONCAT(N'Added ', @sku, N' — ', @name, N'.') AS message;
END;
GO

-- A signed correction: +5 when a count finds more, -3 for damaged or lost.
-- It is a ledger row like every other change and the trigger moves the
-- balance, so stock_levels is never updated directly.
CREATE OR ALTER PROCEDURE dbo.adjust_stock
    @sku VARCHAR(40), @warehouse_code VARCHAR(10), @qty INT, @reason NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @product_id INT, @warehouse_id INT, @on_hand INT, @msg NVARCHAR(400);

    SET @reason = TRIM(@reason);
    SELECT @product_id   = product_id   FROM dbo.products   WHERE sku  = @sku;
    SELECT @warehouse_id = warehouse_id FROM dbo.warehouses WHERE code = @warehouse_code;

    IF @product_id IS NULL          THROW 50030, N'Unknown SKU.', 1;
    IF @warehouse_id IS NULL        THROW 50031, N'Unknown warehouse.', 1;
    IF @qty IS NULL OR @qty = 0     THROW 50032, N'Enter a change other than 0.', 1;
    IF COALESCE(@reason, N'') = N'' THROW 50034, N'Give a reason for the adjustment.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Same lock as transfer_stock. Every change to a balance is the trigger's
        -- UPDATE, which needs an exclusive lock this blocks, so from here to COMMIT
        -- nobody else can move this balance: a concurrent adjustment or transfer
        -- waits, then checks against the new figure. HOLDLOCK covers a missing row
        -- too (nobody can create it meanwhile). ck_stock_levels_quantity is still
        -- the backstop.
        SELECT @on_hand = quantity
        FROM dbo.stock_levels WITH (UPDLOCK, HOLDLOCK)
        WHERE product_id = @product_id AND warehouse_id = @warehouse_id;

        SET @on_hand = COALESCE(@on_hand, 0);   -- no balance row yet = nothing on hand
        IF @on_hand + @qty < 0
        BEGIN
            SET @msg = CONCAT(N'That would take ', @warehouse_code, N' below zero: have ',
                              @on_hand, N', change ', @qty, N'.');
            THROW 50033, @msg, 1;
        END;

        -- ADJUSTMENT is the one movement type allowed to be negative. The trigger
        -- applies it to stock_levels (and creates the balance row if it's missing).
        INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity, reference_type, notes)
        VALUES (@product_id, @warehouse_id, 'ADJUSTMENT', @qty, 'MANUAL', @reason);

        SELECT @on_hand = quantity     -- the balance the trigger just wrote
        FROM dbo.stock_levels
        WHERE product_id = @product_id AND warehouse_id = @warehouse_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;

    SELECT CONCAT(N'Adjusted ', @sku, N' at ', @warehouse_code, N' by ',
                  CASE WHEN @qty > 0 THEN N'+' END, @qty, N'. On hand: ', @on_hand, N'.') AS message;
END;
GO
