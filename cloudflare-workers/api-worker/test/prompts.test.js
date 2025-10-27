// test/prompts.test.js
import { describe, test, expect } from 'vitest';
import { buildCSVParserPrompt, PROMPT_VERSION } from '../src/prompts/csv-parser-prompt.js';

describe('CSV Parser Prompt', () => {
  test('includes few-shot examples', () => {
    const prompt = buildCSVParserPrompt();
    expect(prompt).toContain('Example 1 (Goodreads)');
    expect(prompt).toContain('Example 2 (LibraryThing)');
    expect(prompt).toContain('Example 3 (DNF book)');
  });

  test('includes header variation handling', () => {
    const prompt = buildCSVParserPrompt();
    expect(prompt).toContain('Map common header variations');
  });

  test('has versioning for cache invalidation', () => {
    expect(PROMPT_VERSION).toBe('v1');
  });
});
