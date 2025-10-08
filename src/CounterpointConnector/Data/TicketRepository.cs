using CounterpointConnector.Models;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using System.Data;

namespace CounterpointConnector.Data;

public class TicketRepository : ITicketRepository
{
    private readonly TicketRepositoryOptions _opts;
    public TicketRepository(IOptions<TicketRepositoryOptions> opts)
    {
        _opts = opts.Value;
    }

    public async Task<TicketResult> CreateTicketAsync(string? customerAccountNo, IEnumerable<TicketLine> lines, CancellationToken ct = default)
    {
        if (lines == null || !lines.Any()) throw new ArgumentException("No ticket lines provided.");

        // Build DataTable for TVP matching dbo.TicketLineInput (Sku NVARCHAR(40), Qty INT, OverridePrice DECIMAL(18,2) NULL)
        var tvp = new DataTable();
        tvp.Columns.Add("Sku", typeof(string));
        tvp.Columns.Add("Qty", typeof(int));
        tvp.Columns.Add("OverridePrice", typeof(decimal));

        foreach (var l in lines)
        {
            if (string.IsNullOrWhiteSpace(l.Sku)) throw new ArgumentException("Line SKU required.");
            if (l.Qty <= 0) throw new ArgumentException("Line Qty must be > 0.");
            var ov = l.OverridePrice ?? (decimal)0.00;
            tvp.Rows.Add(l.Sku, l.Qty, ov);
        }

        using var conn = new SqlConnection(_opts.ConnectionString);
        await conn.OpenAsync(ct);

        using var cmd = new SqlCommand("dbo.usp_CreateTicket", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add(new SqlParameter("@CustomerAccountNo", SqlDbType.NVarChar, 40) { Value = (object?)customerAccountNo ?? DBNull.Value });
        var p = cmd.Parameters.Add(new SqlParameter("@Lines", SqlDbType.Structured)
        {
            TypeName = "dbo.TicketLineInput",
            Value = tvp
        });

        // The stored proc returns SELECT of TicketID/Subtotal/TaxAmount/Total; we'll execute and read the first row
        using var reader = await cmd.ExecuteReaderAsync(ct);

        if (!reader.HasRows)
        {
            // No rows returned; consider it an error
            throw new Exception("Stored procedure did not return result.");
        }

        await reader.ReadAsync(ct);

        var ticketId = reader.GetFieldValue<long>(0);
        var subtotal = reader.GetFieldValue<decimal>(1);
        var tax = reader.GetFieldValue<decimal>(2);
        var total = reader.GetFieldValue<decimal>(3);

        return new TicketResult
        {
            TicketID = ticketId,
            Subtotal = subtotal,
            TaxAmount = tax,
            Total = total
        };
    }
}
