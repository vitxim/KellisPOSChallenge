namespace CounterpointConnector.Models;

public class TicketRequest
{
    public string? CustomerAccountNo { get; set; }
    public List<TicketLine>? Lines { get; set; }
}
