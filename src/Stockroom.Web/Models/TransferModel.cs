using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc.Rendering;

namespace Stockroom.Web.Models;

// The transfer form. The data annotations drive both the server-side checks and,
// through jQuery unobtrusive validation, the same checks in the browser.
public sealed class TransferModel : IValidatableObject
{
    [Required(ErrorMessage = "Pick a product.")]
    [Display(Name = "Product")]
    public string? Sku { get; set; }

    [Required(ErrorMessage = "Pick where it's coming from.")]
    [Display(Name = "From")]
    public string? FromWarehouse { get; set; }

    [Required(ErrorMessage = "Pick where it's going.")]
    [Display(Name = "To")]
    public string? ToWarehouse { get; set; }

    // int? rather than int: an empty box then fails [Required] with this message
    // instead of a generic "The value '' is invalid".
    [Required(ErrorMessage = "Enter a quantity.")]
    [Range(1, 100_000, ErrorMessage = "Enter a quantity between 1 and 100,000.")]
    public int? Quantity { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (!string.IsNullOrEmpty(FromWarehouse) && FromWarehouse == ToWarehouse)
            yield return new ValidationResult("Pick a different warehouse.", [nameof(ToWarehouse)]);
    }
}

public sealed record ProductOption
{
    public string Sku { get; init; } = "";
    public string Name { get; init; } = "";
}

public sealed record TransferPageModel(
    TransferModel Form,
    IReadOnlyList<SelectListItem> Products,
    IReadOnlyList<SelectListItem> Warehouses);
