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

-- 6. A DRAFT purchase order can't be received.
--    Plain EXEC, not INSERT ... EXEC: a ROLLBACK inside a procedure called by
--    INSERT ... EXEC raises error 3915, which would hide the real error.
SET @msg = NULL;
BEGIN TRY
    EXEC dbo.receive_purchase_order 'PO-2026-0004';
END TRY
BEGIN CATCH
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
IF @msg LIKE '50011 %' PRINT '6. draft PO cannot be received ................ PASS';
ELSE BEGIN PRINT '6. draft PO cannot be received ................ FAIL'; SET @fail += 1; END;

-- 7. add_product stores the SKU trimmed and upper-cased, and gives the product a
--    zero balance in each of the 3 warehouses, so it is on the Stock page and,
--    being below its reorder point, on Low stock before anything is received.
--    INSERT ... EXEC keeps the success message to check. If add_product fails
--    inside it, all we see is 3915 (see check 6); TRY/CATCH still makes that a
--    FAIL line and lets the other checks run. Run the EXEC on its own for the cause.
DELETE @result;   -- table variables ignore ROLLBACK, so check 5's row is still here
SET @msg = NULL;
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO @result EXEC dbo.add_product ' test-new-001 ', N' Test Widget ', N'Tools', 5.00, 9.99, 10, 50;
    DECLARE @new_sku VARCHAR(40) = (SELECT sku FROM dbo.products WHERE sku = 'TEST-NEW-001');
    DECLARE @new_zero INT = (SELECT COUNT(*) FROM dbo.v_current_stock WHERE sku = 'TEST-NEW-001' AND quantity = 0);
    DECLARE @new_low INT = (SELECT COUNT(*) FROM dbo.v_low_stock_items WHERE sku = 'TEST-NEW-001');
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
IF @new_sku = 'TEST-NEW-001' COLLATE Latin1_General_BIN2 AND @new_zero = 3 AND @new_low = 3
   AND (SELECT message FROM @result) = N'Added TEST-NEW-001 — Test Widget.'
     PRINT '7. add product: 0 on hand in 3 warehouses ..... PASS';
ELSE BEGIN
     PRINT CONCAT('7. add product: ', @new_sku, ', ', @new_zero, ' zero balance(s), ',
                  @new_low, ' on Low stock ... FAIL ', @msg);
     SET @fail += 1;
END;

-- 7b. Only active warehouses get a balance: with WH-CENT closed, the new product
--     has 2 balances and none at WH-CENT. Same TRY/CATCH as check 7.
SET @msg = NULL;
BEGIN TRY
    BEGIN TRAN;
    UPDATE dbo.warehouses SET is_active = 0 WHERE code = 'WH-CENT';
    INSERT INTO @result EXEC dbo.add_product 'TEST-NEW-002', N'Test Widget', N'Tools', 5.00, 9.99, 10, 50;
    DECLARE @new_bal INT = (SELECT COUNT(*) FROM dbo.v_current_stock WHERE sku = 'TEST-NEW-002');
    DECLARE @new_bal_closed INT = (SELECT COUNT(*) FROM dbo.v_current_stock
                                   WHERE sku = 'TEST-NEW-002' AND warehouse_code = 'WH-CENT');
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
IF @new_bal = 2 AND @new_bal_closed = 0 PRINT '7b. closed warehouse gets no balance .......... PASS';
ELSE BEGIN
     PRINT CONCAT('7b. closed warehouse: ', @new_bal, ' balance(s), ', @new_bal_closed,
                  ' at WH-CENT ... FAIL ', @msg);
     SET @fail += 1;
END;

-- 8. add_product refuses a SKU that already exists, in any case, and writes
--    nothing. Plain EXEC, as in check 6.
SET @before = (SELECT COUNT(*) FROM dbo.products);
SET @msg = NULL;
BEGIN TRY
    EXEC dbo.add_product 'elec-aud-001', N'Duplicate', N'Audio', 1.00, 2.00, 10, 50;
END TRY
BEGIN CATCH
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
SET @after = (SELECT COUNT(*) FROM dbo.products);
IF @after = @before AND @msg LIKE '50020 %' PRINT '8. duplicate SKU rejected, nothing written .... PASS';
ELSE BEGIN PRINT '8. duplicate SKU rejected, nothing written .... FAIL'; SET @fail += 1; END;

-- 9. adjust_stock -3 then +5 moves the balance by exactly +2, as two signed
--    ADJUSTMENT rows in the ledger (the trigger does the balance). Same
--    TRY/CATCH as check 7.
DELETE @result;
SET @msg = NULL;
SET @after = NULL;   -- else it still holds check 8's count if the TRY fails early
BEGIN TRY
    BEGIN TRAN;
    SET @before = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
    DECLARE @adj_before INT = (SELECT COUNT(*) FROM dbo.stock_movements
                               WHERE product_id = @p AND warehouse_id = @w AND movement_type = 'ADJUSTMENT');
    INSERT INTO @result EXEC dbo.adjust_stock 'ELEC-AUD-001', 'WH-EAST', -3, N'Damaged';
    INSERT INTO @result EXEC dbo.adjust_stock 'ELEC-AUD-001', 'WH-EAST', 5, N'Cycle count';
    SET @after = (SELECT quantity FROM dbo.stock_levels WHERE product_id = @p AND warehouse_id = @w);
    DECLARE @adj_after INT = (SELECT COUNT(*) FROM dbo.stock_movements
                              WHERE product_id = @p AND warehouse_id = @w AND movement_type = 'ADJUSTMENT');
    ROLLBACK;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
IF @after = @before + 2 AND @adj_after = @adj_before + 2
   AND EXISTS (SELECT 1 FROM @result
               WHERE message = CONCAT(N'Adjusted ELEC-AUD-001 at WH-EAST by +5. On hand: ', @after, N'.'))
     PRINT '9. adjust -3 then +5: +2, two ledger rows ..... PASS';
ELSE BEGIN
     PRINT CONCAT('9. adjust -3 then +5: ', @before, ' -> ', @after, ', ',
                  @adj_after - @adj_before, ' ledger row(s) ... FAIL ', @msg);
     SET @fail += 1;
END;

-- 10. An adjustment that would take stock below zero is refused and writes
--     nothing. Plain EXEC, as in check 6.
SET @before = (SELECT COUNT(*) FROM dbo.stock_movements);
SET @msg = NULL;
BEGIN TRY
    EXEC dbo.adjust_stock 'ELEC-AUD-001', 'WH-EAST', -999999, N'Lost';
END TRY
BEGIN CATCH
    SET @msg = CONCAT(ERROR_NUMBER(), ' ', ERROR_MESSAGE());
END CATCH;
SET @after = (SELECT COUNT(*) FROM dbo.stock_movements);
IF @after = @before AND @msg LIKE '50033 %' PRINT '10. adjustment below zero writes nothing ...... PASS';
ELSE BEGIN PRINT '10. adjustment below zero writes nothing ...... FAIL'; SET @fail += 1; END;

PRINT '';
IF @fail = 0 PRINT 'ALL CHECKS PASSED';
ELSE THROW 50099, N'Verification failed.', 1;
GO
