# Payroll Deduction Eligibility Import – ETL Console App

This is a .NET 8 console application that performs an ETL (Extract, Transform, Load) operation to import employee payroll deduction eligibility data from a CSV file into the database table `dbo.PayrollEligibility`.

---

## 🧩 Functionality

- Loads `payroll_eligibility.csv` from the local file system
- Validates required fields and value types
- Upserts (inserts/updates) data into `dbo.PayrollEligibility` via a SQL `MERGE` statement
- Logs summary of import: total rows, successful imports, and any rejected rows

---

## 📁 Folder Structure

etl/PayrollEligibility
- bin (folder)
- obj (folder)
-payroll_eligibility.csv
-PayrollEligibilityImport.csproj
-PayrollEligibilityImport.sln
-Program.cs

## 🧰 Prerequisites

- [.NET SDK 8.0+](https://dotnet.microsoft.com/en-us/download)
- SQL Server instance with the following table:

```sql
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.PayrollEligibility') AND type = 'U')
BEGIN
	CREATE TABLE dbo.PayrollEligibility ( 
		EmployeeId			NVARCHAR(20) PRIMARY KEY,         
		FirstName			NVARCHAR(100) NOT NULL, 	       
		LastName			NVARCHAR(100) NOT NULL,           
		Eligible			BIT NOT NULL,             
		LimitPerPayPeriod	DECIMAL(18,2) NOT NULL, 
		UpdatedAtUtc		DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()       
	); 
END
GO	
A valid connection string in Program.cs


How to Run

Open terminal and navigate to the etl/PayrollEligibilityImport project folder.

Place your CSV file (e.g. payroll_eligibility.csv) in the same folder or update the file path in Program.cs.

Build the project:
dotnet build


Run the ETL:
dotnet run

📄 CSV Format

Sample payroll_eligibility.csv file (included):

EmployeeId,FirstName,LastName,Eligible,LimitPerPayPeriod
E001,Alex,Sloan,true,200
E002,Kim,Schuler,true,150
E003,Jonah,Treece,false,0

✅ Validation Rules

All fields are required.
Eligible must be either true or false.
LimitPerPayPeriod must be a valid decimal number.



📝 Output

Import complete: Total=3, Success=3, Failed=0

📌 Notes

The import uses a SQL MERGE statement to perform upsert logic.

The UpdatedAtUtc field is set automatically via the database default.

🧪 Testing

You can modify or extend the payroll_eligibility.csv file to test different scenarios (valid and invalid data).

Ensure the SQL Server is running and accessible from the application.

🏁 Status

✅ Completed for interview submission – Kelli's POS Challenge (Part C)