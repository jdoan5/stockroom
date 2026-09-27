using Microsoft.Data.SqlClient;
using Stockroom.Web.Models;

namespace Stockroom.Web.Data;

// Turns the errors the stored procedures THROW into a message for a specific
// form field, so the user sees "Insufficient stock at WH-EAST" under Quantity
// instead of a 500 page. An empty field name means a message for the whole form.
// The field is a property name, and the forms share names (Sku, Quantity), so
// one map serves them all.
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
        [50020] = nameof(AddProductModel.Sku),        // SKU already exists
        [50021] = nameof(AddProductModel.Category),   // unknown category
        [50022] = "",                                 // SKU or name empty
        [50023] = "",                                 // a number out of range
        [50030] = nameof(AdjustModel.Sku),            // unknown SKU
        [50031] = nameof(AdjustModel.Warehouse),      // unknown warehouse
        [50032] = nameof(AdjustModel.Quantity),       // change of 0
        [50033] = nameof(AdjustModel.Quantity),       // would go below zero
        [50034] = nameof(AdjustModel.Reason),         // no reason given
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
        // people moving the same stock at once (a transfer, or an adjustment that
        // removes stock), and the second would go negative. The database refuses;
        // say so in plain words. Any other 547 (a foreign key, say) is a real bug,
        // so let it surface.
        if (ex.Number == 547 && ex.Message.Contains("ck_stock_levels_quantity"))
        {
            field = nameof(TransferModel.Quantity);   // AdjustModel's field has the same name
            message = "Not enough stock — it changed while you were submitting. Try again.";
            return true;
        }

        // 2627/2601 = duplicate key. add_product checks the SKU under a lock, so
        // this is only a backstop for two people adding the same SKU at once.
        // A duplicate anywhere other than products is a real bug.
        if (ex.Number is 2627 or 2601 && ex.Message.Contains("'dbo.products'"))
        {
            field = nameof(AddProductModel.Sku);
            message = "That SKU already exists.";
            return true;
        }

        field = "";
        message = "";
        return false;
    }
}
