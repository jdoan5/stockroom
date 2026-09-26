using Microsoft.AspNetCore.HttpOverrides;
using Stockroom.Web.Data;

// Map snake_case columns (product_name) to PascalCase properties (ProductName).
Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();
builder.Services.AddSingleton<InventoryRepository>();

// In Azure Container Apps, HTTPS ends at Azure's proxy, which forwards plain HTTP
// with X-Forwarded-Proto: https. Trusting those headers lets the app know the
// original request was HTTPS, so HSTS works and nothing redirects in a loop.
// Clearing the known-proxy lists is safe here only because the container is
// reachable solely through that proxy.
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Clear();
});

var app = builder.Build();

app.UseForwardedHeaders();

// The views format money with "C0", which follows the current culture. A Linux
// container sets no locale, so .NET falls back to the invariant culture and prints
// ¤220,008 instead of $220,008. Pin the culture rather than rely on the host's.
app.UseRequestLocalization("en-US");

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
    app.UseHttpsRedirection();
}
app.UseRouting();
app.UseAuthorization();

app.MapStaticAssets();
app.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}")
    .WithStaticAssets();

app.Run();
