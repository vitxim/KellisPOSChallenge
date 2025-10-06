-- Seed data into table for demo purposes

-- 1) Seed TaxRate (if not exists)
IF NOT EXISTS (SELECT 1 FROM dbo.TaxRate WHERE TaxCode = 'TX')
BEGIN
    INSERT INTO dbo.TaxRate (TaxCode, RatePct) VALUES ('TX', 0.0825);
END
IF NOT EXISTS (SELECT 1 FROM dbo.TaxRate WHERE TaxCode = 'NONTAX')
BEGIN
    INSERT INTO dbo.TaxRate (TaxCode, RatePct) VALUES ('NONTAX', 0.0000);
END
GO

-- 2) Seed Items & Inventory (at least 5 items). Use "IF NOT EXISTS by Sku" to avoid duplicates.
-- SKU = stock keeping unit
IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE Sku = 'SKU1001')
BEGIN
    INSERT INTO dbo.Item (Sku, Description, Price, Cost, TaxCode)
    VALUES ('SKU1001', 'Plush Bear',       19.99,  8.00,  'TX');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE Sku = 'SKU1002')
BEGIN
    INSERT INTO dbo.Item (Sku, Description, Price, Cost, TaxCode)
    VALUES ('SKU1002', 'Mug Gift Set',     12.50,  5.00,  'TX');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE Sku = 'SKU1003')
BEGIN
    INSERT INTO dbo.Item (Sku, Description, Price, Cost, TaxCode)
    VALUES ('SKU1003', 'Greeting Card',     3.95,  1.00,  'NONTAX');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE Sku = 'SKU1004')
BEGIN
    INSERT INTO dbo.Item (Sku, Description, Price, Cost, TaxCode)
    VALUES ('SKU1004', 'Keychain',          4.50,  1.25,  'TX');
END

IF NOT EXISTS (SELECT 1 FROM dbo.Item WHERE Sku = 'SKU1005')
BEGIN
    INSERT INTO dbo.Item (Sku, Description, Price, Cost, TaxCode)
    VALUES ('SKU1005', 'Holiday Ornament',  14.99, 6.50,  'TX');
END
GO

-- 3) Create inventories (match item ids)
-- For each item, insert Inventory row if not exists.
INSERT INTO dbo.Inventory (ItemID, OnHandQty)
SELECT it.ItemID, v.OnHandQty
FROM (VALUES
    ('SKU1001', 50),
    ('SKU1002', 25),
    ('SKU1003', 100),
    ('SKU1004', 200),
    ('SKU1005', 30)
) AS v(Sku, OnHandQty)
JOIN dbo.Item it ON it.Sku = v.Sku
WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory inv WHERE inv.ItemID = it.ItemID);
GO

-- 4) Seed Customers (2 customers, one TaxExempt = 1)
IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE AccountNo = 'CUST001')
BEGIN
    INSERT INTO dbo.Customer (AccountNo, Name, TaxExempt)
    VALUES ('CUST001', 'Billy Vo', 0);
END

IF NOT EXISTS (SELECT 1 FROM dbo.Customer WHERE AccountNo = 'CUST002')
BEGIN
    INSERT INTO dbo.Customer (AccountNo, Name, TaxExempt)
    VALUES ('CUST002', 'John Doe', 1);
END
GO