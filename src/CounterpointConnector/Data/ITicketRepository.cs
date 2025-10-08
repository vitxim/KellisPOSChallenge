using CounterpointConnector.Models;

namespace CounterpointConnector.Data;

public interface ITicketRepository
{
    /// <summary>
    /// Calls the stored procedure to create a ticket. Throws InventoryException if validation fails due to inventory.
    /// Returns TicketResult populated by the stored proc.
    /// </summary>
    Task<TicketResult> CreateTicketAsync(string? customerAccountNo, IEnumerable<TicketLine> lines, CancellationToken ct = default);
}
