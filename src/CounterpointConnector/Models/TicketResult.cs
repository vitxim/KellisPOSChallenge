namespace CounterpointConnector.Models;

public class TicketResult
{
    public long TicketID { get; set; }
    public decimal Subtotal { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal Total { get; set; }
}
