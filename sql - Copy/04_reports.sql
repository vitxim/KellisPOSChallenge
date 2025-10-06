-- 1) Nonclustered indexes to speed up queries (create if not exists)
-- Index on Ticket.CreatedAt for date range queries
IF NOT EXISTS (SELECT 1 FROM sys.indexes idx JOIN sys.objects o ON o.object_id = idx.object_id WHERE o.name = 'Ticket' AND idx.name = 'IX_Ticket_CreatedAt')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Ticket_CreatedAt ON dbo.Ticket (CreatedAt);
END
GO

-- Index on TicketLine.ItemID and include Qty, LineSubtotal (helps aggregation by item)
IF NOT EXISTS (SELECT 1 FROM sys.indexes idx JOIN sys.objects o ON o.object_id = idx.object_id WHERE o.name = 'TicketLine' AND idx.name = 'IX_TicketLine_ItemID_Includes')
BEGIN
    CREATE NONCLUSTERED INDEX IX_TicketLine_ItemID_Includes
    ON dbo.TicketLine (ItemID)
    INCLUDE (Qty, LineSubtotal, TicketID);
END
GO

-- 2) Performance Query:
-- Top 10 items by gross margin sold in the last 30 days
-- Columns: Sku, Description, UnitsSold, Revenue, COGS, GrossMargin, GrossMarginPct
/*
Notes:
- Revenue = SUM(LineSubtotal)
- COGS (cost of goods sold)    = SUM(Qty * Item.Cost)
- GrossMargin = Revenue - COGS
- GrossMarginPct = CASE WHEN Revenue = 0 THEN 0 ELSE GrossMargin / Revenue END

- This query uses Ticket.CreatedAt to restrict to last 30 days.
- Indexes recommended above (IX_Ticket_CreatedAt and IX_TicketLine_ItemID_Includes) help:
    * IX_Ticket_CreatedAt lets the engine quickly get TicketIDs in the date window.
    * IX_TicketLine_ItemID_Includes helps aggregate TicketLine rows by ItemID and gives LineSubtotal and Qty without wide lookups.
- We also have unique index IX_TicketLine_Ticket_Item for ticket-line dedup prevention.
*/

SELECT TOP (10)
    i.Sku,
    i.Description,
    UnitsSold = SUM(tl.Qty),
    Revenue = SUM(tl.LineSubtotal),
    COGS = SUM(CAST(tl.Qty AS DECIMAL(18,2)) * i.Cost),
    GrossMargin = SUM(tl.LineSubtotal) - SUM(CAST(tl.Qty AS DECIMAL(18,2)) * i.Cost),
    GrossMarginPct = CASE WHEN SUM(tl.LineSubtotal) = 0 THEN 0
                         ELSE (SUM(tl.LineSubtotal) - SUM(CAST(tl.Qty AS DECIMAL(18,2)) * i.Cost)) / NULLIF(SUM(tl.LineSubtotal),0)
                    END
FROM dbo.TicketLine tl
JOIN dbo.Ticket t ON t.TicketID = tl.TicketID
JOIN dbo.Item i ON i.ItemID = tl.ItemID
WHERE t.CreatedAt >= DATEADD(DAY, -30, GETUTCDATE()) --could also use GETDATE() of Kelli stores are all in Texas
GROUP BY i.Sku, i.Description
ORDER BY GrossMargin DESC;
GO

-- 3) Optional: seed a sample ticket if none exists (keeps re-runnable)
-- This gives me something to test the performance query and the stored proc behavior.
IF NOT EXISTS (SELECT 1 FROM dbo.Ticket)
BEGIN
    -- Insert sample Ticket using the stored procedure to ensure logic is exercised.
    DECLARE @TVP dbo.TicketLineInput;
    INSERT INTO @TVP (Sku, Qty) VALUES ('SKU1001', 1);
    INSERT INTO @TVP (Sku, Qty) VALUES ('SKU1003', 2);
    EXEC dbo.usp_CreateTicket @CustomerAccountNo = 'CUST001', @Lines = @TVP;
END
GO


