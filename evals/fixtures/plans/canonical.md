# Export the department roster as CSV

**Type:** feature
**Asked:** add a CSV option to the department roster export

## Summary
- The roster page already builds the rows; only the output format is missing.
- Add a CSV writer beside the existing XLSX one and a format switch on the page.
- Risk: the two writers drift apart; one row builder feeds both.

## Acceptance criteria
- [ ] `?format=csv` on the roster page downloads a CSV with the same rows as the XLSX
- [ ] a department with no members produces a header-only file, not an error

## Steps
1. [x] Add the CSV writer beside the XLSX one — landed as abc123
   - Create: classes/export/writer/CsvWriter.php
   - Modify: none
   - Test: tests/export/CsvWriterTest.php
   - Check: `vendor/bin/phpunit tests/export/CsvWriterTest.php`

2. [ ] Route `?format=csv` on the roster page to the new writer
   - Create: none
   - Modify: pages/roster.php:40-58 (render_export), classes/export/Format.php
   - Test: tests/pages/RosterExportTest.php
   - Check: `vendor/bin/phpunit tests/pages/RosterExportTest.php`

3. [ ] Cover the empty department
   - Create: none
   - Modify: tests/export/CsvWriterTest.php
   - Test: tests/export/CsvWriterTest.php
   - Check: `vendor/bin/phpunit tests/export/CsvWriterTest.php`

## Do not touch
- `classes/export/writer/XlsxWriter.php` — the CSV writer copies its shape, not its code
