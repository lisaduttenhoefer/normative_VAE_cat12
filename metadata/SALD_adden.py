#!/usr/bin/env python3
"""
SALD Metadata Integration Script
Merges SALD Excel metadata with existing metadata CSV file
"""

import pandas as pd
import sys

# ============================================================================
# CONFIGURATION
# ============================================================================
SALD_EXCEL_FILE = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/sub_information.xlsx"  # Deine SALD Excel-Datei
EXISTING_CSV = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/complete_metadata.csv"   # Deine bestehende Metadaten-Datei
OUTPUT_CSV = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/complete_metadata_all.csv"       # Output-Datei

print("=" * 70)
print("SALD METADATA INTEGRATION")
print("=" * 70)

# ============================================================================
# STEP 1: Read SALD Excel file
# ============================================================================
print("\n[1/5] Reading SALD Excel file...")
try:
    # Try reading from first sheet
    sald_df = pd.read_excel(SALD_EXCEL_FILE)
    print(f"  ✓ Loaded {len(sald_df)} subjects from Excel")
    print(f"  Columns found: {list(sald_df.columns)}")
except Exception as e:
    print(f"  ✗ Error reading Excel file: {e}")
    sys.exit(1)

# ============================================================================
# STEP 2: Process SALD data
# ============================================================================
print("\n[2/5] Processing SALD data...")

# Rename columns to match your existing format
# Adjust these column names based on your Excel structure
column_mapping = {
    'Sub_ID': 'Sub_ID',           # Keep Sub_ID for now
    'Sex': 'Sex',                 # M/F
    'Age': 'Age',                 # Age in years
}

# Select and rename relevant columns
sald_processed = sald_df[list(column_mapping.keys())].copy()
sald_processed.columns = [column_mapping[col] for col in sald_processed.columns]

# Create Filename from Sub_ID: "031274" -> "sub-031274_T1w"
sald_processed['Filename'] = sald_processed['Sub_ID'].apply(lambda x: f"sub-{x}_T1w")

# Add Diagnosis column (all HC for SALD)
sald_processed['Diagnosis'] = 'HC'

# Add Dataset column
sald_processed['Dataset'] = 'SALD'

# Convert Sex encoding if needed (1=F, 2=M based on your screenshot)
print(f"  Original Sex values: {sald_processed['Sex'].unique()}")
print(f"  Sex dtype: {sald_processed['Sex'].dtype}")

if sald_processed['Sex'].dtype in ['int64', 'float64']:
    sex_map = {1: 'Female', 2: 'Male'}
    sex_int_map_direct = {1: 0.0, 2: 1.0}
    sald_processed['Sex_Int'] = sald_processed['Sex'].map(sex_int_map_direct)
    sald_processed['Sex'] = sald_processed['Sex'].map(sex_map)
    print(f"  ✓ Converted Sex encoding (1=Female/0.0, 2=Male/1.0)")
else:
    # If Sex is already F/M, convert to Female/Male
    sex_map = {'F': 'Female', 'M': 'Male'}
    sex_int_map = {'F': 0.0, 'M': 1.0, 'Female': 0.0, 'Male': 1.0}
    sald_processed['Sex_Int'] = sald_processed['Sex'].map(sex_int_map)
    sald_processed['Sex'] = sald_processed['Sex'].map(sex_map)
    print(f"  ✓ Converted Sex encoding (F/M=Female/Male, Sex_Int: F/Female=0.0, M/Male=1.0)")

print(f"  Final Sex values: {sald_processed['Sex'].unique()}")
print(f"  Final Sex_Int values: {sald_processed['Sex_Int'].unique()}")

# Remove Sub_ID column (we now have Filename)
sald_processed = sald_processed.drop('Sub_ID', axis=1)

# Reorder columns to match your existing format
sald_processed = sald_processed[['Filename', 'Dataset', 'Diagnosis', 'Age', 'Sex', 'Sex_Int']]

print(f"  ✓ Created {len(sald_processed)} entries with format:")
print(f"    Columns: {list(sald_processed.columns)}")
print("\n  Example entries:")
print(sald_processed.head(3).to_string(index=False))

# ============================================================================
# STEP 3: Read existing metadata
# ============================================================================
print("\n[3/5] Reading existing metadata file...")
try:
    existing_df = pd.read_csv(EXISTING_CSV)
    print(f"  ✓ Loaded {len(existing_df)} existing subjects")
    print(f"  Columns: {list(existing_df.columns)}")
except Exception as e:
    print(f"  ✗ Error reading existing CSV: {e}")
    sys.exit(1)

# ============================================================================
# STEP 4: Merge datasets
# ============================================================================
print("\n[4/5] Merging datasets...")

# Get all columns from existing dataset
all_columns = list(existing_df.columns)

# Add missing columns to SALD data (fill with NaN/empty)
for col in all_columns:
    if col not in sald_processed.columns:
        sald_processed[col] = None
        print(f"  Added empty column: {col}")

# Reorder SALD columns to match existing dataset
sald_processed = sald_processed[all_columns]

# Concatenate datasets
merged_df = pd.concat([existing_df, sald_processed], ignore_index=True)

print(f"  ✓ Merged dataset contains {len(merged_df)} total subjects")
print(f"    - Original: {len(existing_df)}")
print(f"    - SALD: {len(sald_processed)}")

# ============================================================================
# STEP 5: Save merged dataset
# ============================================================================
print("\n[5/5] Saving merged dataset...")
try:
    merged_df.to_csv(OUTPUT_CSV, index=False)
    print(f"  ✓ Saved to: {OUTPUT_CSV}")
except Exception as e:
    print(f"  ✗ Error saving file: {e}")
    sys.exit(1)

# ============================================================================
# SUMMARY
# ============================================================================
print("\n" + "=" * 70)
print("SUMMARY")
print("=" * 70)
print(f"Total subjects in merged file: {len(merged_df)}")
print(f"  - Original subjects: {len(existing_df)}")
print(f"  - SALD subjects: {len(sald_processed)}")
print(f"\nDiagnosis distribution:")
print(merged_df['Diagnosis'].value_counts().to_string())
print(f"\nSex distribution:")
print(merged_df['Sex'].value_counts().to_string())
print(f"\nAge statistics:")
print(f"  Mean: {merged_df['Age'].mean():.1f} years")
print(f"  Range: {merged_df['Age'].min():.0f} - {merged_df['Age'].max():.0f} years")
print("\n" + "=" * 70)
print(f"✓ Output saved to: {OUTPUT_CSV}")
print("=" * 70)

# Show first few rows of merged data
print("\nFirst 5 rows of merged dataset:")
print(merged_df.head().to_string(index=False))
print("\nLast 5 rows (SALD subjects):")
print(merged_df.tail().to_string(index=False))