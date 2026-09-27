using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace Stockroom.Web.Models;

// The add-product form. As with TransferModel, the annotations drive the checks
// on the server and, through jQuery unobtrusive validation, in the browser.
// add_product re-checks what the data depends on (a SKU and a name, a known
// category, no negative numbers, a unique SKU), so the page isn't the only guard;
// the SKU pattern and the upper limits are checked here only.
public sealed class AddProductModel
{
    [Required(ErrorMessage = "Enter a SKU.")]
    [StringLength(40, ErrorMessage = "Keep the SKU to 40 characters or fewer.")]
    [RegularExpression("^[A-Za-z0-9-]+$", ErrorMessage = "Use only letters, numbers and hyphens, e.g. TOOL-HAM-001.")]
    [Display(Name = "SKU")]
    public string? Sku { get; set; }

    [Required(ErrorMessage = "Enter a name.")]
    [StringLength(200, ErrorMessage = "Keep the name to 200 characters or fewer.")]
    [Display(Name = "Name")]
    public string? Name { get; set; }

    [Required(ErrorMessage = "Pick a category.")]
    [Display(Name = "Category")]
    public string? Category { get; set; }

    // decimal? and int? for the same reason as TransferModel.Quantity: an empty
    // box fails [Required] with a readable message.
    [Required(ErrorMessage = "Enter the unit cost.")]
    [Range(typeof(decimal), "0", "1000000", ErrorMessage = "Enter a cost between 0 and 1,000,000.")]
    [Display(Name = "Unit cost")]
    public decimal? UnitCost { get; set; }

    [Required(ErrorMessage = "Enter the unit price.")]
    [Range(typeof(decimal), "0", "1000000", ErrorMessage = "Enter a price between 0 and 1,000,000.")]
    [Display(Name = "Unit price")]
    public decimal? UnitPrice { get; set; }

    [Required(ErrorMessage = "Enter a reorder point.")]
    [Range(0, 100_000, ErrorMessage = "Enter a reorder point between 0 and 100,000.")]
    [Display(Name = "Reorder point")]
    public int? ReorderPoint { get; set; }

    [Required(ErrorMessage = "Enter a reorder quantity.")]
    [Range(1, 100_000, ErrorMessage = "Enter a reorder quantity between 1 and 100,000.")]
    [Display(Name = "Reorder quantity")]
    public int? ReorderQuantity { get; set; }
}

public sealed record CategoryOption
{
    public string Name { get; init; } = "";
    public string? ParentName { get; init; }
}

public sealed record AddProductPageModel(
    AddProductModel Form,
    IReadOnlyList<SelectListItem> Categories);
