using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Stockroom.Web.Data;

namespace Stockroom.Web.Controllers;

public class PurchaseOrdersController(InventoryRepository repo) : Controller
{
    // GET /PurchaseOrders
    public async Task<IActionResult> Index() => View(await repo.GetPurchaseOrdersAsync());

    // GET /PurchaseOrders/Table — just the table, so jQuery can refresh it in place.
    public async Task<IActionResult> Table() => PartialView("_Table", await repo.GetPurchaseOrdersAsync());

    // POST /PurchaseOrders/Receive — called by jQuery; answers with JSON.
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Receive(string poNumber)
    {
        try
        {
            return Json(new { message = await repo.ReceivePurchaseOrderAsync(poNumber) });
        }
        catch (SqlException ex) when (ProcErrors.TryMap(ex, out _, out var text))
        {
            return BadRequest(new { message = text });
        }
    }
}
