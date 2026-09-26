using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.Data.SqlClient;
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

    // GET /Stock/Transfer
    [HttpGet]
    public async Task<IActionResult> Transfer()
    {
        var products = await repo.GetProductsAsync();
        var warehouses = await repo.GetWarehouseCodesAsync();
        return View(new TransferPageModel(
            new TransferModel(),
            products.Select(p => new SelectListItem($"{p.Sku} — {p.Name}", p.Sku)).ToList(),
            warehouses.Select(w => new SelectListItem(w, w)).ToList()));
    }

    // POST /Stock/Transfer — called by jQuery; answers with JSON.
    //   200 { message }                  the transfer happened
    //   400 { errors: { Field: [..] } }  validation or a stored-procedure rule said no
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Transfer([Bind(Prefix = "Form")] TransferModel form)
    {
        if (!ModelState.IsValid)
            return BadRequest(new { errors = ModelState.ToErrorDictionary() });

        try
        {
            var message = await repo.TransferStockAsync(
                form.Sku!, form.FromWarehouse!, form.ToWarehouse!, form.Quantity!.Value);
            return Json(new { message });
        }
        catch (SqlException ex) when (ProcErrors.TryMap(ex, out var field, out var text))
        {
            return BadRequest(new { errors = new Dictionary<string, string[]> { [field] = [text] } });
        }
    }

    // GET /Stock/ForSku?sku=ELEC-AUD-001 — a small HTML fragment jQuery drops into the page.
    [HttpGet]
    public async Task<IActionResult> ForSku(string sku) =>
        PartialView("_SkuStock", await repo.GetStockForSkuAsync(sku));
}
