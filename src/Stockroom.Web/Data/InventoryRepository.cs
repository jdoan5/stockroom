using Dapper;
using Microsoft.Data.SqlClient;
using Stockroom.Web.Models;

namespace Stockroom.Web.Data;

// All reads go through the Stage 1 views, so the SQL lives in the database and
// the same views feed the Power BI report later. Dapper, not EF Core: the
// queries are plain SQL you can paste into DataGrip and run as-is.
public sealed class InventoryRepository(IConfiguration config)
{
    private readonly string _connectionString =
        config.GetConnectionString("Stockroom")
        ?? throw new InvalidOperationException(
            "Connection string 'Stockroom' is missing. Run the app with `make run`, "
            + "or set ConnectionStrings__Stockroom.");

    private SqlConnection Connect() => new(_connectionString);

    public async Task<IReadOnlyList<ValuationRow>> GetValuationAsync()
    {
        await using var db = Connect();
        var rows = await db.QueryAsync<ValuationRow>("""
            SELECT warehouse_code, warehouse_name, distinct_skus, total_units,
                   valuation_at_cost, valuation_at_retail
            FROM dbo.v_stock_valuation
            ORDER BY warehouse_code;
            """);
        return rows.AsList();
    }

    public async Task<int> CountLowStockAsync()
    {
        await using var db = Connect();
        return await db.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.v_low_stock_items;");
    }

    public async Task<int> CountOpenPurchaseOrdersAsync()
    {
        await using var db = Connect();
        return await db.ExecuteScalarAsync<int>("""
            SELECT COUNT(*) FROM dbo.purchase_orders
            WHERE status IN ('PLACED', 'PARTIALLY_RECEIVED');
            """);
    }

    public async Task<IReadOnlyList<string>> GetWarehouseCodesAsync()
    {
        await using var db = Connect();
        var codes = await db.QueryAsync<string>("SELECT code FROM dbo.warehouses ORDER BY code;");
        return codes.AsList();
    }

    public async Task<IReadOnlyList<StockRow>> GetStockAsync(string? warehouseCode)
    {
        const string columns = """
            SELECT sku, product_name, category, warehouse_code, quantity, reorder_point, last_updated
            FROM dbo.v_current_stock
            """;

        await using var db = Connect();

        // Two separate queries rather than WHERE (@w IS NULL OR warehouse_code = @w).
        // That "catch-all" form gets one cached plan for both cases, which is a
        // classic SQL Server parameter-sniffing trap.
        var rows = string.IsNullOrEmpty(warehouseCode)
            ? await db.QueryAsync<StockRow>(columns + " ORDER BY warehouse_code, sku;")
            : await db.QueryAsync<StockRow>(columns + " WHERE warehouse_code = @warehouseCode ORDER BY sku;",
                                            new { warehouseCode });   // parameterised, never concatenated
        return rows.AsList();
    }

    public async Task<IReadOnlyList<LowStockRow>> GetLowStockAsync()
    {
        await using var db = Connect();
        var rows = await db.QueryAsync<LowStockRow>("""
            SELECT sku, product_name, warehouse_code, quantity, reorder_point,
                   deficit, suggested_order_qty
            FROM dbo.v_low_stock_items
            ORDER BY deficit DESC, sku;
            """);
        return rows.AsList();
    }

    public async Task<IReadOnlyList<PurchaseOrderRow>> GetPurchaseOrdersAsync()
    {
        await using var db = Connect();
        var rows = await db.QueryAsync<PurchaseOrderRow>("""
            SELECT po_number, supplier_name, warehouse_code, status, order_date,
                   expected_date, received_date, line_count, total_ordered,
                   total_received, total_value
            FROM dbo.v_purchase_order_summary
            ORDER BY order_date DESC;
            """);
        return rows.AsList();
    }
}
