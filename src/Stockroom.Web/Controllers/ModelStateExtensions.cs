using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace Stockroom.Web.Controllers;

public static class ModelStateExtensions
{
    // { "Form.Quantity": ["Enter a quantity."] } -> { "Quantity": [...] }
    // The prefix is stripped so the keys match the field names the page knows.
    public static Dictionary<string, string[]> ToErrorDictionary(this ModelStateDictionary state) =>
        state.Where(kv => kv.Value is { Errors.Count: > 0 })
             .ToDictionary(
                 kv => kv.Key.StartsWith("Form.") ? kv.Key["Form.".Length..] : kv.Key,
                 kv => kv.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
