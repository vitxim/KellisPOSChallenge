-- KGS_Demo DB and tables creation:  idempotent/re-runable script

-- 1) Create database if not exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'KGS_Demo')
BEGIN
    CREATE DATABASE KGS_Demo;
END
GO

-- Set compatibility level (safe even if DB already existed)
ALTER DATABASE KGS_Demo SET COMPATIBILITY_LEVEL = 160;
GO

USE KGS_Demo;
GO

-- 2) Create tables (if not exists)
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Item') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Item (
        ItemID       INT IDENTITY PRIMARY KEY,
        Sku          NVARCHAR(40) UNIQUE NOT NULL,
        Description  NVARCHAR(200) NOT NULL,
        Price        DECIMAL(18,2) NOT NULL,
        Cost         DECIMAL(18,2) NOT NULL,
        TaxCode      NVARCHAR(10) NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Inventory') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Inventory (
        ItemID    INT PRIMARY KEY REFERENCES dbo.Item(ItemID),
        OnHandQty INT NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Customer') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Customer (
        CustomerID  INT IDENTITY PRIMARY KEY,
        AccountNo   NVARCHAR(40) UNIQUE NOT NULL,
        Name        NVARCHAR(200) NOT NULL,
        TaxExempt   BIT NOT NULL DEFAULT(0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.TaxRate') AND type = 'U')
BEGIN
    CREATE TABLE dbo.TaxRate (
        TaxCode NVARCHAR(10) PRIMARY KEY,
        RatePct DECIMAL(6,4) NOT NULL    -- e.g., 0.0825 = 8.25%
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.Ticket') AND type = 'U')
BEGIN
    CREATE TABLE dbo.Ticket (
        TicketID   BIGINT IDENTITY PRIMARY KEY,
        CustomerID INT NULL REFERENCES dbo.Customer(CustomerID),
        CreatedAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        Subtotal   DECIMAL(18,2) NOT NULL DEFAULT(0),
        TaxAmount  DECIMAL(18,2) NOT NULL DEFAULT(0),
        Total      DECIMAL(18,2) NOT NULL DEFAULT(0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.TicketLine') AND type = 'U')
BEGIN
    CREATE TABLE dbo.TicketLine (
        TicketLineID BIGINT IDENTITY PRIMARY KEY,
        TicketID     BIGINT NOT NULL REFERENCES dbo.Ticket(TicketID),
        ItemID       INT NOT NULL REFERENCES dbo.Item(ItemID),
        Qty          INT NOT NULL CHECK (Qty > 0),
        UnitPrice    DECIMAL(18,2) NOT NULL,
        LineSubtotal DECIMAL(18,2) NOT NULL
    );
END
GO

-- 3) Create unique index on TicketLine(TicketID, ItemID) if not exists
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes idx
    JOIN sys.objects o ON o.object_id = idx.object_id
    WHERE o.name = 'TicketLine' AND idx.name = 'IX_TicketLine_Ticket_Item'
)
BEGIN
    CREATE UNIQUE INDEX IX_TicketLine_Ticket_Item ON dbo.TicketLine (TicketID, ItemID);
END
GO