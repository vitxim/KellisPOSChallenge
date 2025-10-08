using CounterpointConnector.Data;
using CounterpointConnector.Models;
using CounterpointConnector.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Configuration & logging
builder.Configuration.AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
                     .AddJsonFile("appsettings.Development.json", optional: true, reloadOnChange: true)
                     .AddEnvironmentVariables();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "CounterpointConnector", Version = "v1" });
});

// DI registrations
builder.Services.AddScoped<ITicketRepository, TicketRepository>(); // uses connection string
builder.Services.AddScoped<TicketService>();

// Configure connection string for repo
builder.Services.Configure<TicketRepositoryOptions>(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("DefaultConnection") ??
        throw new InvalidOperationException("DefaultConnection missing in configuration");
});

var app = builder.Build();

if (app.Environment.IsDevelopment()) { app.UseSwagger(); app.UseSwaggerUI(); }

// global minimal exception mapping
app.Use(async (ctx, next) =>
{
    try
    {
        await next();
    }
    catch (InventoryException invEx)
    {
        ctx.Response.StatusCode = 409;
        await ctx.Response.WriteAsJsonAsync(new { error = invEx.Message });
    }
    catch (ArgumentException argEx)
    {
        ctx.Response.StatusCode = 400;
        await ctx.Response.WriteAsJsonAsync(new { error = argEx.Message });
    }
    catch (Exception ex)
    {
        var logger = ctx.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogError(ex, "Unhandled exception for RequestID {RequestId}", ctx.TraceIdentifier);
        ctx.Response.StatusCode = 500;
        await ctx.Response.WriteAsJsonAsync(new { error = "Unexpected server error." });
    }
});

// POST /api/tickets
app.MapPost("/api/tickets", async (TicketRequest ticket, TicketService service, ILogger<Program> logger, HttpContext ctx) =>
{
    // Request ID + non-PII logging
    var reqId = ctx.TraceIdentifier;
    logger.LogInformation("Request {RequestId} received to create ticket (customer provided?: {HasCustomer})", reqId, !string.IsNullOrWhiteSpace(ticket?.CustomerAccountNo));

    var result = await service.CreateTicketAsync(ticket);

    logger.LogInformation("Request {RequestId} succeeded (TicketID {TicketId})", reqId, result.TicketID);
    return Results.Ok(result);
})
.WithName("PostTicket")
.Produces<TicketResult>(StatusCodes.Status200OK)
.Produces(StatusCodes.Status400BadRequest)
.Produces(StatusCodes.Status409Conflict)
.Produces(StatusCodes.Status500InternalServerError);

app.Run();
