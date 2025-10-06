# SQL Deliverables for KGS_Demo

## Run Order
Execute the scripts in the following order:

1. **01_schema.sql**  
   - Creates the database `KGS_Demo` (if not exists).  
   - Defines tables, primary/foreign keys, and indexes.

2. **02_seed.sql**  
   - Inserts initial seed/reference data (e.g., Items, Categories, Tickets).  
   - Safe to re-run; uses conditional inserts where applicable.

3. **03_procs.sql**  
   - Creates stored procedures and user-defined functions used by the application.  
   - Includes error handling and parameter validation.

4. **04_reports.sql**  
   - Defines reporting or analytics queries, views, or report procedures.  
   - Typically read-only logic built on top of the main schema.

---

## Assumptions & Requirements
- Microsoft SQL Server 2022 (RTM) - 16.0.1000.6 (X64)   Express Edition (64-bit)
- The user running the scripts must have `CREATE DATABASE`, `ALTER`, and `EXECUTE` permissions.  
- Default file paths for SQL Server data/log files are assumed.  
- No existing `KGS_Demo` database conflicts.  
- Scripts are idempotent (can be safely re-run without duplication or errors).  
- Run scripts via SQL Server Management Studio (SSMS).

---

## Notes
- Each script uses `IF NOT EXISTS` checks to prevent duplicate creation.  
- The schema is designed for demonstration of POS-related data flow (Items, Tickets, TicketLines).  
- Modify paths or database names as needed for your environment.
