using CounterpointConnector.Data;
using CounterpointConnector.Models;
using CounterpointConnector.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace CounterpointConnector.Tests;

public class TicketServiceTests
{
    [Fact]
    public async Task CreateTicket_HappyPath_ReturnsResult()
    {
        // Arrange
        var repoMock = new Mock<ITicketRepository>();
        var expected = new TicketResult { TicketID = 1001, Subtotal = 10M, TaxAmount = 0.8M, Total = 10.8M };

        repoMock.Setup(r => r.CreateTicketAsync(It.IsAny<string?>(), It.IsAny<IEnumerable<TicketLine>>(), default))
                .ReturnsAsync(expected);

        var logger = NullLogger<TicketService>.Instance;
        var service = new TicketService(repoMock.Object, logger);

        var request = new TicketRequest
        {
            CustomerAccountNo = "CUST1001",
            Lines = new List<TicketLine>
            {
                new() { Sku = "SKU-100", Qty = 2 }
            }
        };

        // Act
        var result = await service.CreateTicketAsync(request);

        // Assert
        Assert.Equal(expected.TicketID, result.TicketID);
        Assert.Equal(expected.Total, result.Total);
    }

    [Fact]
    public async Task CreateTicket_InvalidPayload_ThrowsArgumentException()
    {
        var repoMock = new Mock<ITicketRepository>();
        var logger = NullLogger<TicketService>.Instance;
        var svc = new TicketService(repoMock.Object, logger);

        // invalid: no lines
        var req = new TicketRequest { CustomerAccountNo = "CUST1001", Lines = new List<TicketLine>() };

        await Assert.ThrowsAsync<ArgumentException>(() => svc.CreateTicketAsync(req));
    }

    [Fact]
    public async Task CreateTicket_InventoryIssue_BubblesUpInventoryException()
    {
        var repoMock = new Mock<ITicketRepository>();
        repoMock.Setup(r => r.CreateTicketAsync(It.IsAny<string?>(), It.IsAny<IEnumerable<TicketLine>>(), default))
                .ThrowsAsync(new InventoryException("Insufficient inventory for SKU-100"));

        var logger = NullLogger<TicketService>.Instance;
        var svc = new TicketService(repoMock.Object, logger);

        var req = new TicketRequest
        {
            CustomerAccountNo = "CUST1001",
            Lines = new List<TicketLine> { new() { Sku = "SKU-100", Qty = 10 } }
        };

        await Assert.ThrowsAsync<InventoryException>(() => svc.CreateTicketAsync(req));
    }
}
