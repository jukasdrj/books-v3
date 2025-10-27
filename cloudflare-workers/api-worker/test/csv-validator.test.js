// test/csv-validator.test.js
import { describe, test, expect } from 'vitest';
import { validateCSV } from '../src/utils/csv-validator.js';

describe('CSV Validator', () => {
  test('validates well-formed CSV', () => {
    const csv = 'Title,Author\nBook1,Author1\nBook2,Author2';
    const result = validateCSV(csv);
    expect(result.valid).toBe(true);
    expect(result.rowCount).toBe(2);
  });

  test('rejects empty CSV', () => {
    const result = validateCSV('');
    expect(result.valid).toBe(false);
    expect(result.error).toContain('empty');
  });

  test('rejects CSV with inconsistent columns', () => {
    const csv = 'Title,Author\nBook1,Author1\nBook2';
    const result = validateCSV(csv);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('inconsistent');
  });

  test('handles unclosed quotes gracefully', () => {
    const csv = 'Title,Author\n"Book1,Author1\nBook2,Author2';
    const result = validateCSV(csv);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('quote');
  });

  test('rejects CSV exceeding 10000 rows', () => {
    const rows = Array(10001).fill('Book,Author').join('\n');
    const csv = 'Title,Author\n' + rows;
    const result = validateCSV(csv);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('10000');
  });
});
