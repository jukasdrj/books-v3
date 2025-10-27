// src/utils/csv-validator.js

const MAX_ROWS = 10000;

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
  const columnCount = header.split(',').length;

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

  // Sample check: validate first 10 rows have consistent column count
  const sampleSize = Math.min(10, lines.length - 1);
  for (let i = 1; i <= sampleSize; i++) {
    const cols = lines[i].split(',').length;
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
