using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.Data.SqlClient;
using Stockroom.Web.Data;
using Stockroom.Web.Models;

namespace Stockroom.Web.Controllers;

public class ProductsController(InventoryRepository repo) : Controller
{
    // GET /Products/Add
    [HttpGet]
    public async Task<IActionResult> Add()
    {
        var categories = await repo.GetCategoriesAsync();
        return View(new AddProductPageModel(
            new AddProductModel { ReorderPoint = 10, ReorderQuantity = 50 },   // the table's defaults
            categories.Select(c => new SelectListItem(
                c.ParentName is null ? c.Name : $"{c.ParentName} › {c.Name}", c.Name)).ToList()));
    }

    // POST /Products/Add — called by jQuery; answers with JSON, like Transfer.
    //   200 { message }                  the product was added
    //   400 { errors: { Field: [..] } }  validation or a stored-procedure rule said no
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Add([Bind(Prefix = "Form")] AddProductModel form)
    {
        if (!ModelState.IsValid)
            return BadRequest(new { errors = ModelState.ToErrorDictionary() });

        try
        {
            var message = await repo.AddProductAsync(
                form.Sku!, form.Name!, form.Category!, form.UnitCost!.Value, form.UnitPrice!.Value,
                form.ReorderPoint!.Value, form.ReorderQuantity!.Value);
            return Json(new { message });
        }
        catch (SqlException ex) when (ProcErrors.TryMap(ex, out var field, out var text))
        {
            return BadRequest(new { errors = new Dictionary<string, string[]> { [field] = [text] } });
        }
    }
}
