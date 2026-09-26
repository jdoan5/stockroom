namespace Stockroom.Web.Models;

// One class per reporting view. Dapper maps the snake_case columns onto these
// properties (see MatchNamesWithUnderscores in Program.cs).

public sealed record ValuationRow
{
    public string WarehouseCode { get; init; } = "";
    public string WarehouseName { get; init; } = "";
    public int DistinctSkus { get; init; }
    public int TotalUnits { get; init; }
    public decimal ValuationAtCost { get; init; }
    public decimal ValuationAtRetail { get; init; }
}

public sealed record StockRow
{
    public string Sku { get; init; } = "";
    public string ProductName { get; init; } = "";
    public string? Category { get; init; }
    public string WarehouseCode { get; init; } = "";
    public int Quantity { get; init; }
    public int ReorderPoint { get; init; }
    public DateTime LastUpdated { get; init; }

    public bool IsLow => Quantity < ReorderPoint;
}

public sealed record LowStockRow
{
    public string Sku { get; init; } = "";
    public string ProductName { get; init; } = "";
    public string WarehouseCode { get; init; } = "";
    public int Quantity { get; init; }
    public int ReorderPoint { get; init; }
    public int Deficit { get; init; }
    public int SuggestedOrderQty { get; init; }
}

public sealed record PurchaseOrderRow
{
    public string PoNumber { get; init; } = "";
    public string SupplierName { get; init; } = "";
    public string WarehouseCode { get; init; } = "";
    public string Status { get; init; } = "";
    public DateTime OrderDate { get; init; }
    public DateTime? ExpectedDate { get; init; }
    public DateTime? ReceivedDate { get; init; }
    public int LineCount { get; init; }
    public int TotalOrdered { get; init; }
    public int TotalReceived { get; init; }
    public decimal TotalValue { get; init; }
}

public sealed record DashboardViewModel(
    IReadOnlyList<ValuationRow> Valuation,
    int LowStockCount,
    int OpenPurchaseOrders);

public sealed record StockViewModel(
    IReadOnlyList<StockRow> Rows,
    IReadOnlyList<string> Warehouses,
    string? SelectedWarehouse);
