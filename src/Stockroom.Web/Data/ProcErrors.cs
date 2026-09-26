using Microsoft.Data.SqlClient;
using Stockroom.Web.Models;

namespace Stockroom.Web.Data;

// Turns the errors the stored procedures THROW into a message for a specific
// form field, so the user sees "Insufficient stock at WH-EAST" under Quantity
// instead of a 500 page. An empty field name means a message for the whole form.
public static class ProcErrors
{
    private static readonly Dictionary<int, string> FieldByNumber = new()
    {
        [50001] = nameof(TransferModel.Quantity),     // quantity must be positive
        [50002] = nameof(TransferModel.Sku),          // unknown SKU
        [50003] = "",                                 // unknown warehouse
        [50004] = nameof(TransferModel.ToWarehouse),  // same warehouse twice
        [50005] = nameof(TransferModel.Quantity),     // insufficient stock
        [50010] = "",                                 // unknown purchase order
        [50011] = "",                                 // PO is DRAFT or CANCELLED
    };

    public static bool TryMap(SqlException ex, out string field, out string message)
    {
        if (FieldByNumber.TryGetValue(ex.Number, out var mapped))
        {
            field = mapped;
            message = ex.Message;
            return true;
        }

        // 547 = constraint violation. The one we expect is the stock CHECK: two
        // people transferring the same stock at once, and the second would go
        // negative. The database refuses; say so in plain words. Any other 547
        // (a foreign key, say) is a real bug, so let it surface.
        if (ex.Number == 547 && ex.Message.Contains("ck_stock_levels_quantity"))
        {
            field = nameof(TransferModel.Quantity);
            message = "Not enough stock — it changed while you were submitting. Try again.";
            return true;
        }

        field = "";
        message = "";
        return false;
    }
}
