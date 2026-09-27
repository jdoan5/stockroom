using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace Stockroom.Web.Models;

// The adjust-stock form: a signed change to one warehouse's stock, with the
// reason saved on the movement so the ledger says why the count changed.
public sealed class AdjustModel : IValidatableObject
{
    [Required(ErrorMessage = "Pick a product.")]
    [Display(Name = "Product")]
    public string? Sku { get; set; }

    [Required(ErrorMessage = "Pick a warehouse.")]
    [Display(Name = "Warehouse")]
    public string? Warehouse { get; set; }

    // Signed: +5 = counted more than the system had, -3 = damaged or lost.
    [Required(ErrorMessage = "Enter a quantity.")]
    [Range(-100_000, 100_000, ErrorMessage = "Enter a quantity between -100,000 and 100,000.")]
    public int? Quantity { get; set; }

    [Required(ErrorMessage = "Give a reason for the adjustment.")]
    [StringLength(200, ErrorMessage = "Keep the reason to 200 characters or fewer.")]
    public string? Reason { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Quantity == 0)
            yield return new ValidationResult("Enter a change other than 0.", [nameof(Quantity)]);
    }
}

public sealed record AdjustPageModel(
    AdjustModel Form,
    IReadOnlyList<SelectListItem> Products,
    IReadOnlyList<SelectListItem> Warehouses);
