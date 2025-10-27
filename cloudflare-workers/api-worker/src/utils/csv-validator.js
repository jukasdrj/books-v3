// src/utils/csv-validator.js

export const MAX_ROWS = 10000;
const SAMPLE_VALIDATION_ROWS = 10;

/**
 * Counts columns in a CSV line, respecting quoted fields and escaped quotes.
 * Handles commas inside quotes and CSV-spec-compliant escaped quotes ("") correctly.
 *
 * @param {string} line - CSV line to count columns in
 * @returns {number} Number of columns in the line
 */
function countColumns(line) {
  let count = 1;
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const nextChar = line[i + 1];

    if (char === '"') {
      // Check for escaped quote ("") per RFC 4180
      if (inQuotes && nextChar === '"') {
        i++; // Skip next quote
        continue;
      }
      inQuotes = !inQuotes;
    }
    if (char === ',' && !inQuotes) {
      count++;
    }
  }

  return count;
}

/**
 * Validates CSV structure before expensive Gemini API call.
 * Performs quick checks to reject malformed files early.
 *
 * Validation checks:
 * - Non-empty file
 * - At least header + 1 data row
 * - Maximum 10,000 rows
 * - At least 2 columns
 * - No unclosed quotes
 * - Consistent column count (sampled from first 10 rows)
 *
 * @param {string} csvText - Raw CSV content to validate
 * @returns {{ valid: boolean, error?: string, rowCount?: number, columnCount?: number }}
 *   - valid: true if CSV passes all checks
 *   - error: Error message if validation fails
 *   - rowCount: Number of data rows (excluding header) if valid
 *   - columnCount: Number of columns if valid
 */
export function validateCSV(csvText) {
  // Check for empty input
  if (!csvText || csvText.trim().length === 0) {
    return {
      valid: false,
      error: 'CSV file is empty'
    };
  }

  const lines = csvText.split('\n').filter(line => line.trim());

  // Must have at least header + 1 data row
  if (lines.length < 2) {
    return {
      valid: false,
      error: 'CSV must have at least a header and one data row'
    };
  }

  // Check row limit
  if (lines.length > MAX_ROWS + 1) { // +1 for header
    return {
      valid: false,
      error: `CSV exceeds maximum of ${MAX_ROWS} rows`
    };
  }

  // Validate header exists
  const header = lines[0];
  const columnCount = countColumns(header);

  if (columnCount < 2) {
    return {
      valid: false,
      error: 'CSV must have at least 2 columns'
    };
  }

  // Check for unclosed quotes
  let quoteCount = 0;
  for (const char of csvText) {
    if (char === '"') quoteCount++;
  }
  if (quoteCount % 2 !== 0) {
    return {
      valid: false,
      error: 'CSV has unclosed quotes'
    };
  }

  // Sample check: validate first N rows have consistent column count
  const sampleSize = Math.min(SAMPLE_VALIDATION_ROWS, lines.length - 1);
  for (let i = 1; i <= sampleSize; i++) {
    const cols = countColumns(lines[i]);
    if (cols !== columnCount) {
      return {
        valid: false,
        error: `CSV has inconsistent column count (row ${i + 1})`
      };
    }
  }

  return {
    valid: true,
    rowCount: lines.length - 1, // Exclude header
    columnCount
  };
}
