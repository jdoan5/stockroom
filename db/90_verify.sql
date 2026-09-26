-- 90_verify.sql — quick checks that the port behaves correctly.
-- Tests that change data run inside a transaction and are rolled back.

SET NOCOUNT ON;
DECLARE @fail INT = 0, @before INT, @after INT, @msg NVARCHAR(400);

-- 1. Seed loaded completely (a typo in a seed lookup would silently drop rows)
IF (SELECT COUNT(*) FROM dbo.products) = 15 AND (SELECT COUNT(*) FROM dbo.stock_levels) = 45
   AND (SELECT COUNT(*) FROM dbo.purchase_order_items) = 7 AND (SELECT COUNT(*) FROM dbo.stock_movements) = 8
     PRINT '1. seed row counts ............................ PASS';
ELSE BEGIN PRINT '1. seed row counts ............................ FAIL'; SET @fail += 1; END;

-- 2. A multi-row insert updates every balance (two rows hit the same balance)
BEGIN TRAN;
    DECLARE @p INT = (SELECT product_id FROM dbo.products WHERE sku = 'ELEC-AUD-001');
    DECLARE @w INT = (SELECT warehouse_id FROM dbo.warehouses WHERE code = 'WH-EAST');
    SET @before = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
    INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity)
    VALUES (@p, @w, 'IN', 20), (@p, @w, 'OUT', 5);
    SET @after = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
ROLLBACK;
IF @after = @before + 15 PRINT CONCAT('2. multi-row insert: ', @before, ' -> ', @after, ' ............... PASS');
ELSE BEGIN PRINT CONCAT('2. multi-row insert: ', @before, ' -> ', @after, ' ............... FAIL'); SET @fail += 1; END;

-- 3. Negative ADJUSTMENT is allowed (shrinkage), shipping more than on hand is not
BEGIN TRAN;
    SET @before = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
    INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity) VALUES (@p, @w, 'ADJUSTMENT', -3);
    SET @after = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
ROLLBACK;
IF @after = @before - 3 PRINT '3a. negative adjustment reduces stock ......... PASS';
ELSE BEGIN PRINT '3a. negative adjustment reduces stock ......... FAIL'; SET @fail += 1; END;

SET @msg = NULL;
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO dbo.stock_movements (product_id, warehouse_id, movement_type, quantity) VALUES (@p, @w, 'OUT', 999999);
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @msg = ERROR_MESSAGE();
END CATCH;
IF @msg LIKE '%ck_stock_levels_quantity%' PRINT '3b. overselling is rejected ................... PASS';
ELSE BEGIN PRINT '3b. overselling is rejected ................... FAIL'; SET @fail += 1; END;

-- 4. A failed transfer writes nothing (the procedure is all-or-nothing)
SET @before = (SELECT COUNT(*) FROM dbo.stock_movements);
SET @msg = NULL;
BEGIN TRY
    EXEC dbo.transfer_stock 'ELEC-AUD-001', 'WH-EAST', 'WH-WEST', 999999;
END TRY
BEGIN CATCH
    SET @msg = ERROR_MESSAGE();
END CATCH;
SET @after = (SELECT COUNT(*) FROM dbo.stock_movements);
IF @after = @before AND @msg LIKE 'Insufficient stock%'
     PRINT '4. failed transfer leaves no ledger rows ...... PASS';
ELSE BEGIN PRINT '4. failed transfer leaves no ledger rows ...... FAIL'; SET @fail += 1; END;

-- 5. Receiving a PO updates stock for EVERY line and marks it RECEIVED.
--    PO-2026-0003 has two lines, written in one statement — so both must be
--    checked. (Checking only one let a row-at-a-time trigger pass this test.)
BEGIN TRAN;
    DECLARE @paper_before INT = (SELECT quantity FROM dbo.v_current_stock WHERE sku = 'OFFC-PAP-001' AND warehouse_code = 'WH-EAST');
    DECLARE @stapler_before INT = (SELECT quantity FROM dbo.v_current_stock WHERE sku = 'OFFC-STP-001' AND warehouse_code = 'WH-EAST');
    DECLARE @result TABLE (message NVARCHAR(400));
    INSERT INTO @result EXEC dbo.receive_purchase_order 'PO-2026-0003';
    DECLARE @paper_after INT = (SELECT quantity FROM dbo.v_current_stock WHERE sku = 'OFFC-PAP-001' AND warehouse_code = 'WH-EAST');
    DECLARE @stapler_after INT = (SELECT quantity FROM dbo.v_current_stock WHERE sku = 'OFFC-STP-001' AND warehouse_code = 'WH-EAST');
    DECLARE @status VARCHAR(20) = (SELECT status FROM dbo.purchase_orders WHERE po_number = 'PO-2026-0003');
ROLLBACK;
IF @paper_after = @paper_before + 200 AND @stapler_after = @stapler_before + 40 AND @status = 'RECEIVED'
     PRINT '5. receive PO: both lines stocked, RECEIVED ... PASS';
ELSE BEGIN
     PRINT CONCAT('5. receive PO: paper ', @paper_before, '->', @paper_after, ', stapler ',
                  @stapler_before, '->', @stapler_after, ', ', @status, ' ... FAIL');
     SET @fail += 1;
END;

PRINT '';
IF @fail = 0 PRINT 'ALL CHECKS PASSED';
ELSE THROW 50099, N'Verification failed.', 1;
GO
