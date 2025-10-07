-- 1) Create scalar function: dbo.ufn_GetTaxAmount(@TaxCode, @Amount)
-- Returns computed tax amount (rounded to 2 decimals).
-- Rounding choice: SQL Server ROUND(...,2) is used here (standard rounding: half away from zero).
IF OBJECT_ID('dbo.ufn_GetTaxAmount', 'FN') IS NOT NULL
    DROP FUNCTION dbo.ufn_GetTaxAmount;
GO

CREATE FUNCTION dbo.ufn_GetTaxAmount
(
    @TaxCode NVARCHAR(10),
    @Amount DECIMAL(18,2)
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Rate DECIMAL(6,4) = 0.0000;
    SELECT @Rate = RatePct FROM dbo.TaxRate WHERE TaxCode = @TaxCode;

    -- If no matching TaxCode, treat as 0% (could THROW but instruction didn't specified).
    IF @Rate IS NULL SET @Rate = 0.0000;

    DECLARE @Tax DECIMAL(18,6) = @Amount * @Rate;

    -- Round to 2 decimals using ROUND (standard SQL Server rounding).
    DECLARE @TaxRounded DECIMAL(18,2) = ROUND(@Tax, 2);

    RETURN @TaxRounded;
END;
GO

-- 2) Create TVP type for input lines
IF TYPE_ID(N'dbo.TicketLineInput') IS NOT NULL
    DROP TYPE dbo.TicketLineInput;
GO

CREATE TYPE dbo.TicketLineInput AS TABLE
(
    Sku NVARCHAR(40) NOT NULL,
    Qty INT NOT NULL,
    OverridePrice DECIMAL(18,2) NULL
);
GO

-- 3) Create stored procedure dbo.usp_CreateTicket
--    Input: @CustomerAccountNo NVARCHAR(40) = NULL, @Lines dbo.TicketLineInput READONLY
--    Behavior: validation, transactional, inventory decrement, create Ticket and TicketLines.
IF OBJECT_ID('dbo.usp_CreateTicket', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CreateTicket;
GO

CREATE PROCEDURE [dbo].[usp_CreateTicket]
    @CustomerAccountNo NVARCHAR(40) = NULL,
    @Lines dbo.TicketLineInput READONLY
AS
BEGIN
    SET NOCOUNT ON;

    -- Basic validation
    IF NOT EXISTS (SELECT 1 FROM @Lines)
    BEGIN
        RAISERROR('No ticket lines provided.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;
    BEGIN TRY
        -- a) Resolve customer (if provided)
        DECLARE @CustomerID INT = NULL;
        DECLARE @CustomerTaxExempt BIT = 0;

        IF @CustomerAccountNo IS NOT NULL
        BEGIN
            SELECT @CustomerID = CustomerID, @CustomerTaxExempt = TaxExempt
            FROM dbo.Customer
            WHERE AccountNo = @CustomerAccountNo;

            IF @CustomerID IS NULL
            BEGIN
                RAISERROR('Customer not found: %s', 16, 1, @CustomerAccountNo);
                RETURN;
            END
        END

        -- b) Aggregate input lines by SKU to handle duplicate SKUs
        DECLARE @AggLines TABLE
        (
            Sku NVARCHAR(40) PRIMARY KEY,
            QtyTotal INT,
            OverridePrice DECIMAL(18,2) NULL
        );

        INSERT INTO @AggLines (Sku, QtyTotal, OverridePrice)
        SELECT
            Sku,
            SUM(Qty) AS QtyTotal,
            MAX(OverridePrice) AS OverridePrice
        FROM @Lines
        GROUP BY Sku;

        -- c) Check for missing SKUs (replacing CTE with table variable)
        DECLARE @MissingSkus TABLE (Sku NVARCHAR(40));

        INSERT INTO @MissingSkus (Sku)
        SELECT a.Sku
        FROM @AggLines a
        LEFT JOIN dbo.Item it ON it.Sku = a.Sku
        WHERE it.ItemID IS NULL;

        IF EXISTS (SELECT 1 FROM @MissingSkus)
        BEGIN
            DECLARE @MissingList NVARCHAR(MAX) = (
                SELECT STRING_AGG(Sku, ', ') FROM @MissingSkus
            );
            RAISERROR('The following SKU(s) do not exist: %s', 16, 1, @MissingList);
            RETURN;
        END

        -- d) Check inventory sufficiency (replacing CTE with table variable)
        DECLARE @LineWithItem TABLE
        (
            Sku NVARCHAR(40),
            QtyTotal INT,
            OverridePrice DECIMAL(18,2),
            ItemID INT,
            ItemPrice DECIMAL(18,2),
            ItemCost DECIMAL(18,2),
            TaxCode NVARCHAR(10),
            OnHandQty INT
        );

        INSERT INTO @LineWithItem (Sku, QtyTotal, OverridePrice, ItemID, ItemPrice, ItemCost, TaxCode, OnHandQty)
        SELECT
            a.Sku,
            a.QtyTotal,
            a.OverridePrice,
            it.ItemID,
            it.Price,
            it.Cost,
            it.TaxCode,
            inv.OnHandQty
        FROM @AggLines a
        JOIN dbo.Item it ON it.Sku = a.Sku
        LEFT JOIN dbo.Inventory inv ON inv.ItemID = it.ItemID;

        IF EXISTS (
            SELECT 1
            FROM @LineWithItem
            WHERE ISNULL(OnHandQty, 0) < QtyTotal
        )
        BEGIN
            DECLARE @ErrBody NVARCHAR(MAX) = (
                SELECT STRING_AGG(CONCAT(Sku, ' (Need=', QtyTotal, ', OnHand=', ISNULL(OnHandQty,0)), '; ')
                FROM @LineWithItem
                WHERE ISNULL(OnHandQty, 0) < QtyTotal
            );
            RAISERROR('Insufficient inventory for: %s', 16, 1, @ErrBody);
            RETURN;
        END

        -- e) Compute line amounts and insert Ticket + TicketLine
        DECLARE @Subtotal DECIMAL(18,2) = 0;
        DECLARE @TaxAmount DECIMAL(18,2) = 0;
        DECLARE @Total DECIMAL(18,2) = 0;

        DECLARE @ComputedLines TABLE
        (
            ItemID INT PRIMARY KEY,
            Sku NVARCHAR(40),
            Qty INT,
            UnitPrice DECIMAL(18,2),
            LineSubtotal DECIMAL(18,2),
            TaxCode NVARCHAR(10),
            LineTax DECIMAL(18,2),
            ItemCost DECIMAL(18,2)
        );

        INSERT INTO @ComputedLines (ItemID, Sku, Qty, UnitPrice, LineSubtotal, TaxCode, LineTax, ItemCost)
        SELECT
            lwi.ItemID,
            lwi.Sku,
            lwi.QtyTotal,
            COALESCE(lwi.OverridePrice, lwi.ItemPrice),
            ROUND(lwi.QtyTotal * COALESCE(lwi.OverridePrice, lwi.ItemPrice), 2),
            lwi.TaxCode,
            0.00,
            lwi.ItemCost
        FROM @LineWithItem lwi;

        -- Tax calculation
        IF @CustomerTaxExempt = 1
        BEGIN
            UPDATE @ComputedLines SET LineTax = 0.00;
        END
        ELSE
        BEGIN
            UPDATE cl
            SET LineTax = dbo.ufn_GetTaxAmount(cl.TaxCode, cl.LineSubtotal)
            FROM @ComputedLines cl;
        END

        -- Totals
        SELECT
            @Subtotal = ROUND(ISNULL(SUM(LineSubtotal), 0), 2),
            @TaxAmount = ROUND(ISNULL(SUM(LineTax), 0), 2)
        FROM @ComputedLines;

        SET @Total = ROUND(@Subtotal + @TaxAmount, 2);

        -- Insert Ticket
        DECLARE @NewTicketID BIGINT;
        INSERT INTO dbo.Ticket (CustomerID, Subtotal, TaxAmount, Total)
        VALUES (@CustomerID, @Subtotal, @TaxAmount, @Total);

        SET @NewTicketID = SCOPE_IDENTITY();

        -- Insert TicketLines
        INSERT INTO dbo.TicketLine (TicketID, ItemID, Qty, UnitPrice, LineSubtotal)
        SELECT @NewTicketID, ItemID, Qty, UnitPrice, LineSubtotal
        FROM @ComputedLines
        ORDER BY ItemID;

        -- Update inventory
        UPDATE inv
        SET inv.OnHandQty = inv.OnHandQty - cl.Qty
        FROM dbo.Inventory inv
        JOIN @ComputedLines cl ON cl.ItemID = inv.ItemID;

        COMMIT TRANSACTION;

        -- Return result
        SELECT
            TicketID = @NewTicketID,
            Subtotal = @Subtotal,
            TaxAmount = @TaxAmount,
            Total = @Total;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrNum INT = ERROR_NUMBER();
        DECLARE @ErrState INT = ERROR_STATE();

        THROW @ErrNum, @ErrMsg, @ErrState;
    END CATCH
END;
GO

-- Rounding note:
-- dbo.ufn_GetTaxAmount uses SQL Server ROUND(value, 2) to round tax to 2 decimals.
-- SQL Server ROUND uses standard rounding behavior (round half away from zero),
-- which is commonly acceptable in retail scenarios. 

-- 4) Optional: seed a sample ticket if none exists (keeps re-runnable)
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
