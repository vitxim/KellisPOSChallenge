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

CREATE PROCEDURE dbo.usp_CreateTicket
    @CustomerAccountNo NVARCHAR(40) = NULL,
    @Lines dbo.TicketLineInput READONLY
AS
BEGIN
    SET NOCOUNT ON;

    -- Basic validation
    IF NOT EXISTS (SELECT 1 FROM @Lines)
    BEGIN
        THROW 51001, 'No ticket lines provided.', 1;
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
                THROW 51002, CONCAT('Customer not found: ', @CustomerAccountNo), 1;
            END
        END

        -- b) Aggregate input lines by SKU to handle duplicate SKUs in input.
        --    If multiple OverridePrice values exist for same SKU, choose MAX(OverridePrice) when not null.
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

        -- c) Join aggregated lines to items; check SKUs exist
        ;WITH MissingSkus AS (
            SELECT a.Sku
            FROM @AggLines a
            LEFT JOIN dbo.Item it ON it.Sku = a.Sku
            WHERE it.ItemID IS NULL
        )
        SELECT @CustomerID = @CustomerID -- no-op to satisfy syntax
        -- If any missing SKUs, throw error
        IF EXISTS (SELECT 1 FROM MissingSkus)
        BEGIN
            DECLARE @MissingList NVARCHAR(MAX) = (
                SELECT STRING_AGG(Sku, ', ') FROM MissingSkus
            );
            THROW 51003, CONCAT('The following SKU(s) do not exist: ', @MissingList), 1;
        END

        -- d) Check inventory sufficiency (compare OnHandQty >= QtyTotal)
        ;WITH LineWithItem AS (
            SELECT
                a.Sku,
                a.QtyTotal,
                a.OverridePrice,
                it.ItemID,
                it.Price AS ItemPrice,
                it.Cost AS ItemCost,
                it.TaxCode,
                inv.OnHandQty
            FROM @AggLines a
            JOIN dbo.Item it ON it.Sku = a.Sku
            LEFT JOIN dbo.Inventory inv ON inv.ItemID = it.ItemID
        )
        SELECT @CustomerID = @CustomerID -- no-op
        IF EXISTS (
            SELECT 1
            FROM LineWithItem lwi
            WHERE ISNULL(lwi.OnHandQty, 0) < lwi.QtyTotal
        )
        BEGIN
            -- build message listing SKUs with insufficient qty
            DECLARE @ErrBody NVARCHAR(MAX) = (
                SELECT STRING_AGG(CONCAT(Sku, ' (Need=', QtyTotal, ', OnHand=', ISNULL(OnHandQty,0)), '; ')
                FROM LineWithItem
                WHERE ISNULL(OnHandQty, 0) < QtyTotal
            );
            THROW 51004, CONCAT('Insufficient inventory for: ', @ErrBody), 1;
        END

        -- e) Compute line amounts, totals, and insert Ticket + TicketLine; decrement inventory
        DECLARE @Subtotal DECIMAL(18,2) = 0;
        DECLARE @TaxAmount DECIMAL(18,2) = 0;
        DECLARE @Total DECIMAL(18,2) = 0;

        -- Prepare a table variable with computed per-line values to insert
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
            it.ItemID,
            a.Sku,
            a.QtyTotal AS Qty,
            COALESCE(a.OverridePrice, it.Price) AS UnitPrice,
            ROUND(a.QtyTotal * COALESCE(a.OverridePrice, it.Price), 2) AS LineSubtotal,
            it.TaxCode,
            0.00 AS LineTax,
            it.Cost AS ItemCost
        FROM @AggLines a
        JOIN dbo.Item it ON it.Sku = a.Sku;

        -- Compute tax per line (respecting customer tax exempt)
        IF @CustomerTaxExempt = 1
        BEGIN
            -- leave taxes as 0
            UPDATE @ComputedLines SET LineTax = 0.00;
        END
        ELSE
        BEGIN
            UPDATE cl
            SET LineTax = dbo.ufn_GetTaxAmount(cl.TaxCode, cl.LineSubtotal)
            FROM @ComputedLines cl;
        END

        -- Sum totals
        SELECT
            @Subtotal = ROUND(ISNULL(SUM(LineSubtotal), 0), 2),
            @TaxAmount = ROUND(ISNULL(SUM(LineTax), 0), 2)
        FROM @ComputedLines;

        SET @Total = ROUND(@Subtotal + @TaxAmount, 2);

        -- Insert Ticket and get TicketID
        DECLARE @NewTicketID BIGINT;
        INSERT INTO dbo.Ticket (CustomerID, Subtotal, TaxAmount, Total)
        VALUES (@CustomerID, @Subtotal, @TaxAmount, @Total);

        SET @NewTicketID = SCOPE_IDENTITY();

        -- Insert TicketLine rows
        INSERT INTO dbo.TicketLine (TicketID, ItemID, Qty, UnitPrice, LineSubtotal)
        SELECT @NewTicketID, ItemID, Qty, UnitPrice, LineSubtotal
        FROM @ComputedLines
        ORDER BY ItemID;

        -- Decrement inventory (use update join)
        UPDATE inv
        SET inv.OnHandQty = inv.OnHandQty - cl.Qty
        FROM dbo.Inventory inv
        JOIN @ComputedLines cl ON cl.ItemID = inv.ItemID;

        -- Commit
        COMMIT TRANSACTION;

        -- Return result (TicketID + totals)
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

        -- Re-throw original error
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