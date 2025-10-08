namespace CounterpointConnector.Models;

public class TicketLine
{
    public string? Sku { get; set; }
    public int Qty { get; set; }
    public decimal? OverridePrice { get; set; }
}
