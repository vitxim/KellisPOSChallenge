using System;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using CsvHelper;

class Program
{
    static void Main()
    {
        string csvPath = "payroll_eligibility.csv";
        //string connectionString = "Server=localhost;Database=KellisPOS;Trusted_Connection=True;TrustServerCertificate=True;";
        string connectionString = "Server=DESKTOP-MVDS3BN,1433;Database=KGS_Demo;Trusted_Connection=True;TrustServerCertificate=True;";

        try
        {
            using (SqlConnection connTest = new SqlConnection(connectionString))
            {
                connTest.Open();
                Console.WriteLine("✅ Connected successfully to SQL Server!");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("❌ Connection failed: " + ex.Message);
            return; // Stop program if DB connection fails
        }

        // ⬇️ Your existing ETL logic starts below
        Console.WriteLine("Starting ETL process...");

        int total = 0, success = 0, failed = 0;

        using var reader = new StreamReader(csvPath);
        using var csv = new CsvReader(reader, CultureInfo.InvariantCulture);
        //csv.Context.ReaderConfiguration.PrepareHeaderForMatch = (header, index) => header.Trim();
        csv.Context.Configuration.PrepareHeaderForMatch = args => args.Header.Trim();
        var records = csv.GetRecords<PayrollEligibility>();

        using var conn = new SqlConnection(connectionString);
        conn.Open();

        foreach (var r in records)
        {
            total++;
            try
            {
                // Basic validation
                if (string.IsNullOrWhiteSpace(r.EmployeeId) || r.LimitPerPayPeriod < 0)
                    throw new Exception("Invalid data");

                // Upsert via MERGE
                string sql = @"
                    MERGE dbo.PayrollEligibility AS target
                    USING (SELECT @EmployeeId AS EmployeeId, @FirstName AS FirstName, @LastName AS LastName, @Eligible AS Eligible, @Limit AS LimitPerPayPeriod) AS src
                    ON target.EmployeeId = src.EmployeeId
                    WHEN MATCHED THEN
                        UPDATE SET FirstName = src.FirstName, LastName = src.LastName, Eligible = src.Eligible, LimitPerPayPeriod = src.LimitPerPayPeriod, UpdatedAtUtc = SYSUTCDATETIME()
                    WHEN NOT MATCHED THEN
                        INSERT (EmployeeId, FirstName, LastName, Eligible, LimitPerPayPeriod)
                        VALUES (src.EmployeeId, src.FirstName, src.LastName, src.Eligible, src.LimitPerPayPeriod);";

                using var cmd = new SqlCommand(sql, conn);
                cmd.Parameters.AddWithValue("@EmployeeId", r.EmployeeId);
                cmd.Parameters.AddWithValue("@FirstName", r.FirstName);
                cmd.Parameters.AddWithValue("@LastName", r.LastName);
                cmd.Parameters.AddWithValue("@Eligible", r.Eligible);
                cmd.Parameters.AddWithValue("@Limit", r.LimitPerPayPeriod);
                cmd.ExecuteNonQuery();

                success++;
            }
            catch (Exception ex)
            {
                failed++;
                Console.WriteLine($"Row failed ({r.EmployeeId}): {ex.Message}");
            }
        }

        Console.WriteLine($"Import complete: Total={total}, Success={success}, Failed={failed}");
    }
}

class PayrollEligibility
{
    public string EmployeeId { get; set; }
    public string FirstName { get; set; }
    public string LastName { get; set; }
    public bool Eligible { get; set; }
    public decimal LimitPerPayPeriod { get; set; }
}
