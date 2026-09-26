using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Stockroom.Web.Data;
using Stockroom.Web.Models;

namespace Stockroom.Web.Controllers;

public class HomeController(InventoryRepository repo) : Controller
{
    public async Task<IActionResult> Index()
    {
        var model = new DashboardViewModel(
            await repo.GetValuationAsync(),
            await repo.CountLowStockAsync(),
            await repo.CountOpenPurchaseOrdersAsync());
        return View(model);
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error() =>
        View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
}
