#!/usr/bin/env python3
"""
Output verification script 
Verifies that sorted files are correctly sorted and match between implementations
"""

import struct
import sys
import os
from typing import List, Tuple

def read_records(filename: str) -> List[Tuple[int, bytes]]:
    """Read all records from a binary file and return list of (key, payload) tuples"""
    records = []
    try:
        with open(filename, 'rb') as f:
            while True:
                # Read record header (key + length)
                header = f.read(12)  # 8 bytes key + 4 bytes length
                if len(header) < 12:
                    break
                
                # Unpack header: key (unsigned long long) + length (unsigned int)
                key, length = struct.unpack('<QI', header)
                
                # Validate length
                if length < 8 or length > 4096:  # Assuming PAYLOAD_MAX = 4096
                    print(f"Warning: Invalid payload length {length} at position {f.tell()-12}")
                    continue
                
                # Read payload
                payload = f.read(length)
                if len(payload) != length:
                    print(f"Warning: Could not read full payload at position {f.tell()}")
                    break
                
                records.append((key, payload))
                
    except Exception as e:
        print(f"Error reading file {filename}: {e}")
        return []
    
    return records

def verify_sorted(records: List[Tuple[int, bytes]]) -> bool:
    """Verify that records are sorted by key"""
    if len(records) <= 1:
        return True
    
    for i in range(1, len(records)):
        if records[i][0] < records[i-1][0]:
            print(f"Error: Records not sorted at position {i}")
            print(f"  Previous key: {records[i-1][0]}")
            print(f"  Current key: {records[i][0]}")
            return False
    
    return True

def compare_files(file1: str, file2: str) -> bool:
    """Compare two sorted files record by record"""
    print(f"Comparing {file1} and {file2}...")
    
    if not os.path.exists(file1):
        print(f"Error: {file1} does not exist")
        return False
    
    if not os.path.exists(file2):
        print(f"Error: {file2} does not exist")
        return False
    
    records1 = read_records(file1)
    records2 = read_records(file2)
    
    if len(records1) != len(records2):
        print(f"Error: Different number of records ({len(records1)} vs {len(records2)})")
        return False
    
    # Verify both files are sorted
    if not verify_sorted(records1):
        print(f"Error: {file1} is not properly sorted")
        return False
    
    if not verify_sorted(records2):
        print(f"Error: {file2} is not properly sorted")
        return False

    # Compare record by record
    mismatches = 0
    for i, ((key1, payload1), (key2, payload2)) in enumerate(zip(records1, records2)):
        if key1 != key2:
            print(f"Key mismatch at record {i}: {key1} vs {key2}")
            mismatches += 1
        elif payload1 != payload2:
            print(f"Payload mismatch at record {i} (key {key1})")
            mismatches += 1
        
        # Stop after reporting too many mismatches
        if mismatches > 10:
            print("Too many mismatches, stopping comparison...")
            break
    
    if mismatches == 0:
        print("✓ Files are identical and properly sorted")
        return True
    else:
        print(f"✗ Found {mismatches} mismatches")
        return False

def verify_single_file(filename: str) -> bool:
    """Verify that a single file is properly sorted"""
    print(f"Verifying {filename}...")
    
    if not os.path.exists(filename):
        print(f"Error: {filename} does not exist")
        return False
    
    records = read_records(filename)
    print(f"Read {len(records)} records")
    
    if verify_sorted(records):
        print("✓ File is properly sorted")
        return True
    else:
        print("✗ File is not properly sorted")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 verify_output.py <file1> [file2]")
        print("  - If one file: verify it's sorted")
        print("  - If two files: compare they're identical and sorted")
        sys.exit(1)
    
    file1 = sys.argv[1]
    
    if len(sys.argv) == 2:
        # Verify single file
        success = verify_single_file(file1)
    else:
        # Compare two files
        file2 = sys.argv[2]
        success = compare_files(file1, file2)
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()