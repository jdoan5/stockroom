using Microsoft.AspNetCore.Mvc;
using Stockroom.Web.Data;

namespace Stockroom.Web.Controllers;

public class PurchaseOrdersController(InventoryRepository repo) : Controller
{
    // GET /PurchaseOrders
    public async Task<IActionResult> Index() => View(await repo.GetPurchaseOrdersAsync());
}
