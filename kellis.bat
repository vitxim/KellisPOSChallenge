# Create a .gitignore file (ignore system and temp files)
echo "bin/
obj/
*.user
*.log
*.tmp
*.bak
*.ldf
*.mdf
.vs/
.DS_Store
Thumbs.db" > .gitignore

# Create a README.md
echo "# Kelli's POS Challenge
## Prerequisites
- SQL Server Express or Developer Edition
- .NET 8 SDK

## Setup Steps
1. Run SQL scripts in order:
   - \`sql/01_schema.sql\`
   - \`sql/02_seed.sql\`
   - \`sql/03_procs.sql\`
   - \`sql/04_reports.sql\`

2. Verify the database and stored procedures compile successfully.

3. (Optional) Run ETL and tests if implemented later.

## Notes
- All scripts were tested with SQL Server 2022 Express.
- Uses standard ROUND() for tax calculations.
- Tradeoffs and assumptions documented in-line within scripts.
" > README.md

# Initialize Git and commit
git init
git add .
git commit -m "Initial commit - project structure and SQL files"

# Connect your GitHub repo
git remote add origin https://github.com/vitxim/KellisPOSChallenge.git
git branch -M main

# Push to GitHub
git push -u origin main
