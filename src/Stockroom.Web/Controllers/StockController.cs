using Microsoft.AspNetCore.Mvc;
using Stockroom.Web.Data;
using Stockroom.Web.Models;

namespace Stockroom.Web.Controllers;

public class StockController(InventoryRepository repo) : Controller
{
    // GET /Stock?warehouse=WH-EAST
    public async Task<IActionResult> Index(string? warehouse)
    {
        var model = new StockViewModel(
            await repo.GetStockAsync(warehouse),
            await repo.GetWarehouseCodesAsync(),
            warehouse);
        return View(model);
    }

    // GET /Stock/Low
    public async Task<IActionResult> Low() => View(await repo.GetLowStockAsync());
}
