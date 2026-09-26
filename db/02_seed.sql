-- 02_seed.sql — same sample data as the PostgreSQL original.
-- Loaded before the triggers, so these historical movements don't change stock_levels.

SET NOCOUNT ON;

-- ----------------------------------------------------------------------------
-- categories — two levels
-- ----------------------------------------------------------------------------
INSERT INTO dbo.categories (name, parent_id)
VALUES (N'Electronics', NULL), (N'Furniture', NULL), (N'Office Supplies', NULL),
       (N'Tools', NULL), (N'Clothing', NULL);

INSERT INTO dbo.categories (name, parent_id)
SELECT v.name, p.category_id
FROM (VALUES
        (N'Laptops', N'Electronics'),
        (N'Audio',   N'Electronics'),
        (N'Desks',   N'Furniture'),
        (N'Chairs',  N'Furniture')
     ) AS v (name, parent_name)
JOIN dbo.categories AS p ON p.name = v.parent_name;


-- ----------------------------------------------------------------------------
-- suppliers
-- ----------------------------------------------------------------------------
INSERT INTO dbo.suppliers (name, contact_email, phone, address, city, country)
VALUES
    (N'Acme Electronics Co.',  'sales@acme-elec.com',     '+1-415-555-0101', N'100 Market St', N'San Francisco', N'USA'),
    (N'Globex Furniture Ltd.', 'orders@globex-fur.com',   '+1-312-555-0142', N'22 Lake Shore', N'Chicago',       N'USA'),
    (N'Initech Office Goods',  'hello@initech.com',       '+1-512-555-0188', N'500 Congress',  N'Austin',        N'USA'),
    (N'Hooli Tools Mfg.',      'support@hooli-tools.com', '+1-206-555-0177', N'7 Tech Way',    N'Seattle',       N'USA'),
    (N'Vandelay Apparel',      'sales@vandelay.com',      '+1-212-555-0199', N'88 Broadway',   N'New York',      N'USA');


-- ----------------------------------------------------------------------------
-- warehouses
-- ----------------------------------------------------------------------------
INSERT INTO dbo.warehouses (code, name, address, city, country)
VALUES
    ('WH-WEST', N'West Coast DC', N'1 Logistics Blvd', N'Los Angeles', N'USA'),
    ('WH-CENT', N'Central DC',    N'500 Hub Road',     N'Dallas',      N'USA'),
    ('WH-EAST', N'East Coast DC', N'900 Atlantic Ave', N'Newark',      N'USA');


-- ----------------------------------------------------------------------------
-- products
-- ----------------------------------------------------------------------------
INSERT INTO dbo.products
    (sku, name, description, category_id, unit_price, unit_cost, reorder_point, reorder_quantity)
SELECT v.sku, v.name, v.description, c.category_id,
       v.unit_price, v.unit_cost, v.reorder_point, v.reorder_quantity
FROM (VALUES
    ('ELEC-LAP-001', N'UltraBook 14"',           N'14-inch business laptop',     N'Laptops',         1299.00,  850.00,  15,  40),
    ('ELEC-LAP-002', N'GamerPro 17"',            N'17-inch gaming laptop',       N'Laptops',         1899.00, 1300.00,   8,  20),
    ('ELEC-AUD-001', N'NoiseCancel Headphones',  N'Over-ear ANC headphones',     N'Audio',            249.00,  140.00,  25,  75),
    ('ELEC-AUD-002', N'Bluetooth Speaker',       N'Portable BT speaker',         N'Audio',             79.00,   38.00,  30, 100),
    ('FURN-DSK-001', N'Standing Desk 60"',       N'Electric height-adjustable',  N'Desks',            599.00,  340.00,  10,  25),
    ('FURN-DSK-002', N'Compact Writing Desk',    N'Small home-office desk',      N'Desks',            199.00,  110.00,  12,  30),
    ('FURN-CHR-001', N'Ergonomic Mesh Chair',    N'Lumbar-support office chair', N'Chairs',           329.00,  180.00,  15,  40),
    ('FURN-CHR-002', N'Executive Leather Chair', N'Premium executive chair',     N'Chairs',           549.00,  310.00,   8,  20),
    ('OFFC-PEN-001', N'Gel Pen Pack (12)',       N'Black gel pens, dozen',       N'Office Supplies',    9.99,    3.50,  50, 200),
    ('OFFC-PAP-001', N'A4 Copy Paper 500ct',     N'Multipurpose white paper',    N'Office Supplies',   12.49,    6.00, 100, 300),
    ('OFFC-STP-001', N'Heavy-Duty Stapler',      N'50-sheet capacity',           N'Office Supplies',   24.99,   11.00,  20,  60),
    ('TOOL-DRL-001', N'Cordless Drill 18V',      N'Brushless drill + battery',   N'Tools',            159.00,   85.00,  15,  40),
    ('TOOL-SAW-001', N'Circular Saw 7-1/4"',     N'Corded circular saw',         N'Tools',            129.00,   70.00,  10,  30),
    ('CLTH-TSH-001', N'Cotton T-Shirt (M)',      N'Crew-neck, medium',           N'Clothing',          14.99,    5.50,  40, 150),
    ('CLTH-JKT-001', N'Rain Jacket (L)',         N'Waterproof shell, large',     N'Clothing',          89.00,   42.00,  20,  60)
    ) AS v (sku, name, description, category_name, unit_price, unit_cost, reorder_point, reorder_quantity)
JOIN dbo.categories AS c ON c.name = v.category_name;


-- ----------------------------------------------------------------------------
-- stock_levels — a mix of healthy / low / zero so reorder queries find things
-- ----------------------------------------------------------------------------
INSERT INTO dbo.stock_levels (product_id, warehouse_id, quantity)
SELECT p.product_id, w.warehouse_id,
       CASE
           WHEN p.sku = 'ELEC-LAP-001' AND w.code = 'WH-WEST' THEN   8   -- below reorder
           WHEN p.sku = 'ELEC-LAP-001' AND w.code = 'WH-CENT' THEN  42
           WHEN p.sku = 'ELEC-LAP-001' AND w.code = 'WH-EAST' THEN  27
           WHEN p.sku = 'ELEC-LAP-002' AND w.code = 'WH-WEST' THEN  12
           WHEN p.sku = 'ELEC-LAP-002' AND w.code = 'WH-CENT' THEN   3   -- below reorder
           WHEN p.sku = 'ELEC-LAP-002' AND w.code = 'WH-EAST' THEN  18
           WHEN p.sku = 'ELEC-AUD-001'                        THEN  60
           WHEN p.sku = 'ELEC-AUD-002' AND w.code = 'WH-EAST' THEN  22   -- below reorder
           WHEN p.sku = 'ELEC-AUD-002'                        THEN  85
           WHEN p.sku = 'FURN-DSK-001'                        THEN  18
           WHEN p.sku = 'FURN-DSK-002' AND w.code = 'WH-CENT' THEN   0   -- stock-out
           WHEN p.sku = 'FURN-DSK-002'                        THEN  35
           WHEN p.sku = 'FURN-CHR-001'                        THEN  30
           WHEN p.sku = 'FURN-CHR-002' AND w.code = 'WH-WEST' THEN   5   -- below reorder
           WHEN p.sku = 'FURN-CHR-002'                        THEN  16
           WHEN p.sku = 'OFFC-PEN-001'                        THEN 180
           WHEN p.sku = 'OFFC-PAP-001'                        THEN 260
           WHEN p.sku = 'OFFC-STP-001' AND w.code = 'WH-EAST' THEN  12   -- below reorder
           WHEN p.sku = 'OFFC-STP-001'                        THEN  55
           WHEN p.sku = 'TOOL-DRL-001'                        THEN  28
           WHEN p.sku = 'TOOL-SAW-001'                        THEN  19
           WHEN p.sku = 'CLTH-TSH-001'                        THEN 120
           WHEN p.sku = 'CLTH-JKT-001' AND w.code = 'WH-WEST' THEN  15   -- below reorder
           WHEN p.sku = 'CLTH-JKT-001'                        THEN  45
           ELSE 25
       END
FROM dbo.products AS p
CROSS JOIN dbo.warehouses AS w;


-- ----------------------------------------------------------------------------
-- purchase_orders — one of each status
-- ----------------------------------------------------------------------------
INSERT INTO dbo.purchase_orders
    (po_number, supplier_id, warehouse_id, status, order_date, expected_date, received_date)
SELECT v.po_number, s.supplier_id, w.warehouse_id, v.status,
       v.order_date, v.expected_date, v.received_date
FROM (VALUES
    ('PO-2026-0001', N'Acme Electronics Co.',  'WH-WEST', 'RECEIVED',           CAST('2026-05-01' AS DATE), CAST('2026-05-10' AS DATE), CAST('2026-05-09' AS DATE)),
    ('PO-2026-0002', N'Globex Furniture Ltd.', 'WH-CENT', 'PARTIALLY_RECEIVED', CAST('2026-05-15' AS DATE), CAST('2026-05-25' AS DATE), NULL),
    ('PO-2026-0003', N'Initech Office Goods',  'WH-EAST', 'PLACED',             CAST('2026-05-28' AS DATE), CAST('2026-06-08' AS DATE), NULL),
    ('PO-2026-0004', N'Hooli Tools Mfg.',      'WH-CENT', 'DRAFT',              CAST('2026-06-04' AS DATE), NULL,                       NULL)
    ) AS v (po_number, supplier_name, warehouse_code, status, order_date, expected_date, received_date)
JOIN dbo.suppliers  AS s ON s.name = v.supplier_name
JOIN dbo.warehouses AS w ON w.code = v.warehouse_code;


-- ----------------------------------------------------------------------------
-- purchase_order_items
-- ----------------------------------------------------------------------------
INSERT INTO dbo.purchase_order_items
    (po_id, product_id, quantity_ordered, quantity_received, unit_cost)
SELECT po.po_id, p.product_id, v.quantity_ordered, v.quantity_received, v.unit_cost
FROM (VALUES
    ('PO-2026-0001', 'ELEC-LAP-001',  30, 30, 850.00),   -- received
    ('PO-2026-0001', 'ELEC-AUD-001',  50, 50, 140.00),
    ('PO-2026-0002', 'FURN-DSK-001',  20, 12, 340.00),   -- partial
    ('PO-2026-0002', 'FURN-CHR-001',  25,  0, 180.00),
    ('PO-2026-0003', 'OFFC-PAP-001', 200,  0,   6.00),   -- placed, nothing received
    ('PO-2026-0003', 'OFFC-STP-001',  40,  0,  11.00),
    ('PO-2026-0004', 'TOOL-DRL-001',  30,  0,  85.00)    -- draft
    ) AS v (po_number, sku, quantity_ordered, quantity_received, unit_cost)
JOIN dbo.purchase_orders AS po ON po.po_number = v.po_number
JOIN dbo.products        AS p  ON p.sku        = v.sku;


-- ----------------------------------------------------------------------------
-- stock_movements — historical ledger (trigger not installed yet, on purpose)
--
-- ----------------------------------------------------------------------------
INSERT INTO dbo.stock_movements
    (product_id, warehouse_id, movement_type, quantity, reference_type, reference_id, notes, created_at)
SELECT p.product_id, w.warehouse_id, v.movement_type, v.quantity,
       v.reference_type,
       COALESCE(po.po_id, v.reference_id),
       v.notes, v.created_at
FROM (VALUES
    ('ELEC-LAP-001', 'WH-WEST', 'IN',           30, 'PURCHASE_ORDER', 'PO-2026-0001', NULL, N'Receipt from Acme',      CAST('2026-05-09 10:15:00' AS DATETIME2(0))),
    ('ELEC-AUD-001', 'WH-WEST', 'IN',           50, 'PURCHASE_ORDER', 'PO-2026-0001', NULL, N'Receipt from Acme',      CAST('2026-05-09 10:20:00' AS DATETIME2(0))),
    ('ELEC-LAP-001', 'WH-WEST', 'OUT',          12, 'SALES_ORDER',    NULL,           9001, N'Bulk customer order',    CAST('2026-05-20 14:00:00' AS DATETIME2(0))),
    ('ELEC-AUD-002', 'WH-EAST', 'OUT',           8, 'SALES_ORDER',    NULL,           9002, N'Retail fulfillment',     CAST('2026-05-22 09:30:00' AS DATETIME2(0))),
    ('OFFC-PEN-001', 'WH-CENT', 'ADJUSTMENT',    5, 'MANUAL',         NULL,           NULL, N'Cycle count correction', CAST('2026-05-25 16:45:00' AS DATETIME2(0))),
    ('CLTH-TSH-001', 'WH-WEST', 'OUT',          25, 'SALES_ORDER',    NULL,           9003, N'Wholesale order',        CAST('2026-05-30 11:00:00' AS DATETIME2(0))),
    ('ELEC-AUD-001', 'WH-CENT', 'TRANSFER_OUT', 10, 'TRANSFER',       NULL,           7001, N'To East DC',             CAST('2026-06-01 08:00:00' AS DATETIME2(0))),
    ('ELEC-AUD-001', 'WH-EAST', 'TRANSFER_IN',  10, 'TRANSFER',       NULL,           7001, N'From Central DC',        CAST('2026-06-02 14:30:00' AS DATETIME2(0)))
    ) AS v (sku, warehouse_code, movement_type, quantity, reference_type, po_number, reference_id, notes, created_at)
JOIN      dbo.products        AS p  ON p.sku        = v.sku
JOIN      dbo.warehouses      AS w  ON w.code       = v.warehouse_code
-- LEFT JOIN: most movements have no PO.
LEFT JOIN dbo.purchase_orders AS po ON po.po_number = v.po_number;
GO
