-- 01_schema.sql — Stockroom (SQL Server 2022)
-- Ported from the PostgreSQL schema in jdoan5/Databases-and-Data-Platforms.

SET NOCOUNT ON;

DROP TABLE IF EXISTS dbo.stock_movements, dbo.purchase_order_items, dbo.purchase_orders,
                     dbo.stock_levels, dbo.products, dbo.suppliers, dbo.warehouses, dbo.categories;
GO

-- Note: in SQL Server, TIMESTAMP means rowversion, not a date. Dates use DATETIME2.

CREATE TABLE dbo.categories (
    category_id INT IDENTITY PRIMARY KEY,
    name        NVARCHAR(100) NOT NULL UNIQUE,
    parent_id   INT NULL REFERENCES dbo.categories (category_id),  -- self-FK can't cascade in SQL Server
    created_at  DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.suppliers (
    supplier_id   INT IDENTITY PRIMARY KEY,
    name          NVARCHAR(150) NOT NULL,
    contact_email VARCHAR(150) NULL CHECK (contact_email LIKE '%@%.%'),
    phone         VARCHAR(30) NULL,
    address       NVARCHAR(255) NULL,
    city          NVARCHAR(80) NULL,
    country       NVARCHAR(80) NULL,
    is_active     BIT NOT NULL DEFAULT 1,
    created_at    DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.warehouses (
    warehouse_id INT IDENTITY PRIMARY KEY,
    code         VARCHAR(10) NOT NULL UNIQUE,
    name         NVARCHAR(150) NOT NULL,
    address      NVARCHAR(255) NULL,
    city         NVARCHAR(80) NULL,
    country      NVARCHAR(80) NULL,
    is_active    BIT NOT NULL DEFAULT 1,
    created_at   DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.products (
    product_id       INT IDENTITY PRIMARY KEY,
    sku              VARCHAR(40) NOT NULL UNIQUE,
    name             NVARCHAR(200) NOT NULL,
    description      NVARCHAR(MAX) NULL,
    category_id      INT NULL REFERENCES dbo.categories (category_id) ON DELETE SET NULL,
    unit_price       DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    unit_cost        DECIMAL(12,2) NOT NULL CHECK (unit_cost >= 0),
    reorder_point    INT NOT NULL DEFAULT 10 CHECK (reorder_point >= 0),
    reorder_quantity INT NOT NULL DEFAULT 50 CHECK (reorder_quantity > 0),
    is_active        BIT NOT NULL DEFAULT 1,
    created_at       DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.stock_levels (
    product_id   INT NOT NULL REFERENCES dbo.products (product_id) ON DELETE CASCADE,
    warehouse_id INT NOT NULL REFERENCES dbo.warehouses (warehouse_id) ON DELETE CASCADE,
    quantity     INT NOT NULL DEFAULT 0 CONSTRAINT ck_stock_levels_quantity CHECK (quantity >= 0),
    last_updated DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    PRIMARY KEY (product_id, warehouse_id)
);

CREATE TABLE dbo.purchase_orders (
    po_id         INT IDENTITY PRIMARY KEY,
    po_number     VARCHAR(20) NOT NULL UNIQUE,
    supplier_id   INT NOT NULL REFERENCES dbo.suppliers (supplier_id),
    warehouse_id  INT NOT NULL REFERENCES dbo.warehouses (warehouse_id),
    status        VARCHAR(20) NOT NULL DEFAULT 'DRAFT'    -- was a Postgres ENUM
        CHECK (status IN ('DRAFT','PLACED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
    order_date    DATE NOT NULL DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    expected_date DATE NULL,
    received_date DATE NULL,
    notes         NVARCHAR(MAX) NULL,
    created_at    DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CHECK (expected_date IS NULL OR expected_date >= order_date),
    CHECK (received_date IS NULL OR received_date >= order_date)
);

CREATE TABLE dbo.purchase_order_items (
    po_item_id        INT IDENTITY PRIMARY KEY,
    po_id             INT NOT NULL REFERENCES dbo.purchase_orders (po_id) ON DELETE CASCADE,
    product_id        INT NOT NULL REFERENCES dbo.products (product_id),
    quantity_ordered  INT NOT NULL CHECK (quantity_ordered > 0),
    quantity_received INT NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
    unit_cost         DECIMAL(12,2) NOT NULL CHECK (unit_cost >= 0),
    CHECK (quantity_received <= quantity_ordered),
    UNIQUE (po_id, product_id)
);

CREATE TABLE dbo.stock_movements (
    movement_id    BIGINT IDENTITY PRIMARY KEY,
    product_id     INT NOT NULL REFERENCES dbo.products (product_id),
    warehouse_id   INT NOT NULL REFERENCES dbo.warehouses (warehouse_id),
    movement_type  VARCHAR(20) NOT NULL                  -- was a Postgres ENUM
        CHECK (movement_type IN ('IN','OUT','TRANSFER_IN','TRANSFER_OUT','ADJUSTMENT','RETURN')),
    quantity       INT NOT NULL,
    reference_type VARCHAR(30) NULL,
    reference_id   INT NULL,
    notes          NVARCHAR(MAX) NULL,
    created_at     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    -- ADJUSTMENT may be negative (shrinkage); every other type is positive.
    -- (The Postgres original required > 0 for all, so shrinkage couldn't be recorded.)
    CHECK (quantity <> 0 AND (movement_type = 'ADJUSTMENT' OR quantity > 0))
);

CREATE INDEX ix_stock_movements_created ON dbo.stock_movements (created_at DESC);
GO
