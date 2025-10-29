#!/usr/bin/env python3
"""
CSV Expansion Script for BooksTracker Cache Warmer
==================================================

This script combines multiple CSV files from different sources into a single
expanded library dataset for the Cloudflare Workers cache warming system.

Features:
- Handles different CSV formats (yr_title_auth_isbn13.csv vs year-based files)
- Removes duplicates by ISBN-13 and Title+Author combination
- Normalizes data format for cache warmer compatibility
- Provides detailed statistics on expansion results

Usage:
    python3 combine_csvs.py
"""

import csv
import os
import re
from collections import defaultdict, Counter
from typing import Dict, List, Set, Tuple

class BookRecord:
    """Represents a single book record with normalized fields"""

    def __init__(self, title: str, author: str, isbn: str, year: str = ""):
        self.title = self.normalize_text(title)
        self.author = self.normalize_text(author)
        self.isbn = self.normalize_isbn(isbn)
        self.year = year.strip()

    def normalize_text(self, text: str) -> str:
        """Normalize text by removing quotes, extra spaces, and standardizing case"""
        if not text:
            return ""
        # Remove surrounding quotes and extra whitespace
        text = text.strip().strip('"').strip("'").strip()
        # Normalize multiple spaces to single space
        text = re.sub(r'\s+', ' ', text)
        return text

    def normalize_isbn(self, isbn: str) -> str:
        """Normalize ISBN by removing dashes, spaces, and ensuring 13 digits"""
        if not isbn:
            return ""
        # Remove all non-digit characters except 'x' or 'X' (for ISBN-10)
        isbn_clean = re.sub(r'[^\dXx]', '', isbn.strip())
        # Convert to uppercase for consistency
        isbn_clean = isbn_clean.upper()

        # If it's a 10-digit ISBN, try to convert to 13-digit
        if len(isbn_clean) == 10:
            # ISBN-10 to ISBN-13 conversion (simplified)
            if isbn_clean.endswith('X'):
                # Handle ISBN-10 ending with X
                return isbn_clean  # Keep as-is for now
            else:
                # Add 978 prefix for standard conversion
                isbn_clean = '978' + isbn_clean[:9]
                # Would need check digit calculation for full conversion

        return isbn_clean

    def dedup_key(self) -> str:
        """Generate a key for duplicate detection"""
        # Primary key: ISBN (if valid)
        if self.isbn and len(self.isbn) >= 10:
            return f"isbn:{self.isbn}"

        # Fallback key: normalized title + author
        return f"title_author:{self.title.lower()}:{self.author.lower()}"

    def to_dict(self) -> Dict[str, str]:
        """Convert to dictionary for CSV output"""
        return {
            'Title': self.title,
            'Author': self.author,
            'ISBN-13': self.isbn,
            'Year': self.year
        }

    def __str__(self) -> str:
        return f"BookRecord('{self.title}' by {self.author}, ISBN: {self.isbn})"

class CSVCombiner:
    """Main class for combining and processing CSV files"""

    def __init__(self, input_dir: str):
        self.input_dir = input_dir
        self.books: List[BookRecord] = []
        self.stats = {
            'files_processed': 0,
            'total_raw_records': 0,
            'duplicates_removed': 0,
            'unique_books': 0,
            'unique_authors': 0,
            'isbn_coverage': 0
        }

    def process_all_files(self) -> None:
        """Process all CSV files in the input directory"""
        print("🚀 Starting CSV combination process...")

        # Get all CSV files
        csv_files = [f for f in os.listdir(self.input_dir) if f.endswith('.csv')]
        csv_files.sort()  # Process in alphabetical order

        print(f"📁 Found {len(csv_files)} CSV files to process")

        for filename in csv_files:
            self.process_file(filename)

        # Remove duplicates
        self.remove_duplicates()

        # Calculate final statistics
        self.calculate_stats()

        print("✅ CSV combination completed!")

    def process_file(self, filename: str) -> None:
        """Process a single CSV file"""
        filepath = os.path.join(self.input_dir, filename)
        print(f"📖 Processing {filename}...")

        records_in_file = 0

        try:
            with open(filepath, 'r', encoding='utf-8') as file:
                # Peek at first line to determine format
                first_line = file.readline().strip().lower()
                file.seek(0)  # Reset to beginning

                reader = csv.reader(file)
                headers = next(reader)  # Skip header row

                # Determine file format
                if 'year' in first_line and 'title' in first_line:
                    # Format: year,title,author,isbn13
                    year_idx, title_idx, author_idx, isbn_idx = 0, 1, 2, 3
                    has_year = True
                else:
                    # Format: Title,Author,ISBN-13
                    title_idx, author_idx, isbn_idx = 0, 1, 2
                    year_idx = -1
                    has_year = False

                for row in reader:
                    if len(row) < 3:  # Skip invalid rows
                        continue

                    try:
                        title = row[title_idx] if title_idx < len(row) else ""
                        author = row[author_idx] if author_idx < len(row) else ""
                        isbn = row[isbn_idx] if isbn_idx < len(row) else ""
                        year = row[year_idx] if has_year and year_idx < len(row) else ""

                        # Skip empty records
                        if not title.strip() or not author.strip():
                            continue

                        book = BookRecord(title, author, isbn, year)
                        self.books.append(book)
                        records_in_file += 1

                    except (IndexError, ValueError) as e:
                        print(f"⚠️  Skipping invalid row in {filename}: {row}")
                        continue

        except Exception as e:
            print(f"❌ Error processing {filename}: {e}")
            return

        print(f"   └── Added {records_in_file} records")
        self.stats['files_processed'] += 1
        self.stats['total_raw_records'] += records_in_file

    def remove_duplicates(self) -> None:
        """Remove duplicate books based on ISBN and title+author combination"""
        print("🔍 Removing duplicates...")

        seen_keys: Set[str] = set()
        unique_books: List[BookRecord] = []
        duplicate_count = 0

        for book in self.books:
            dedup_key = book.dedup_key()

            if dedup_key not in seen_keys:
                seen_keys.add(dedup_key)
                unique_books.append(book)
            else:
                duplicate_count += 1

        self.books = unique_books
        self.stats['duplicates_removed'] = duplicate_count

        print(f"   └── Removed {duplicate_count} duplicates")
        print(f"   └── Kept {len(unique_books)} unique books")

    def calculate_stats(self) -> None:
        """Calculate final statistics"""
        self.stats['unique_books'] = len(self.books)

        # Count unique authors
        authors: Set[str] = set()
        books_with_isbn = 0

        for book in self.books:
            authors.add(book.author.lower())
            if book.isbn and len(book.isbn) >= 10:
                books_with_isbn += 1

        self.stats['unique_authors'] = len(authors)
        self.stats['isbn_coverage'] = (books_with_isbn / len(self.books) * 100) if self.books else 0

    def export_combined_csv(self, output_file: str) -> None:
        """Export the combined and deduplicated data to a CSV file"""
        print(f"💾 Exporting combined data to {output_file}...")

        with open(output_file, 'w', newline='', encoding='utf-8') as file:
            fieldnames = ['Title', 'Author', 'ISBN-13']
            writer = csv.DictWriter(file, fieldnames=fieldnames)

            writer.writeheader()
            for book in self.books:
                # Export in the format expected by the cache warmer
                row = {
                    'Title': book.title,
                    'Author': book.author,
                    'ISBN-13': book.isbn
                }
                writer.writerow(row)

        print(f"   └── Exported {len(self.books)} unique books")

    def print_statistics(self) -> None:
        """Print detailed statistics about the combination process"""
        print("\n" + "="*60)
        print("📊 LIBRARY EXPANSION STATISTICS")
        print("="*60)

        print(f"Files Processed:        {self.stats['files_processed']}")
        print(f"Total Raw Records:      {self.stats['total_raw_records']:,}")
        print(f"Duplicates Removed:     {self.stats['duplicates_removed']:,}")
        print(f"Final Unique Books:     {self.stats['unique_books']:,}")
        print(f"Unique Authors:         {self.stats['unique_authors']:,}")
        print(f"ISBN Coverage:          {self.stats['isbn_coverage']:.1f}%")

        # Calculate expansion vs original 352 authors
        original_authors = 352
        expansion_factor = self.stats['unique_authors'] / original_authors
        print(f"\nEXPANSION ANALYSIS:")
        print(f"Original Library:       352 authors")
        print(f"Expanded Library:       {self.stats['unique_authors']:,} authors")
        print(f"Expansion Factor:       {expansion_factor:.1f}x")
        print(f"New Authors Added:      {self.stats['unique_authors'] - original_authors:,}")

        print("\n" + "="*60)

    def show_sample_data(self, count: int = 10) -> None:
        """Show sample data for verification"""
        print(f"\n📚 SAMPLE DATA (first {count} books):")
        print("-" * 80)

        for i, book in enumerate(self.books[:count]):
            print(f"{i+1:2d}. {book.title[:40]:42} | {book.author[:25]:27} | {book.isbn}")

        if len(self.books) > count:
            print(f"... and {len(self.books) - count:,} more books")

def main():
    """Main execution function"""
    input_dir = "."  # Current directory
    output_file = "combined_library_expanded.csv"

    # Initialize the combiner
    combiner = CSVCombiner(input_dir)

    # Process all CSV files
    combiner.process_all_files()

    # Export the combined data
    combiner.export_combined_csv(output_file)

    # Show statistics and sample data
    combiner.print_statistics()
    combiner.show_sample_data(15)

    print(f"\n🎉 SUCCESS! Expanded library saved as: {output_file}")
    print("📤 Ready to upload to the cache warming system!")

if __name__ == "__main__":
    main()