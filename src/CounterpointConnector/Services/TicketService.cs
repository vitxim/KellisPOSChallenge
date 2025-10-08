using CounterpointConnector.Data;
using CounterpointConnector.Models;

namespace CounterpointConnector.Services;

public class TicketService
{
    private readonly ITicketRepository _repo;
    private readonly ILogger<TicketService> _logger;

    public TicketService(ITicketRepository repo, ILogger<TicketService> logger)
    {
        _repo = repo;
        _logger = logger;
    }

    public async Task<TicketResult> CreateTicketAsync(TicketRequest? req)
    {
        if (req == null) throw new ArgumentException("Request body is required.");
        if (req.Lines == null || !req.Lines.Any()) throw new ArgumentException("Ticket must include at least one line.");

        // lightweight validation
        foreach (var line in req.Lines)
        {
            if (line == null) throw new ArgumentException("Line cannot be null.");
            if (string.IsNullOrWhiteSpace(line.Sku)) throw new ArgumentException("Each line must have a SKU.");
            if (line.Qty <= 0) throw new ArgumentException("Each line must have Qty > 0.");
        }

        try
        {
            var result = await _repo.CreateTicketAsync(req.CustomerAccountNo, req.Lines);
            return result;
        }
        catch (InventoryException)
        {
            _logger.LogWarning("Inventory validation failed for customer {Customer}", req.CustomerAccountNo);
            throw; // rethrow to be handled by middleware (mapped to 409)
        }
    }
}
