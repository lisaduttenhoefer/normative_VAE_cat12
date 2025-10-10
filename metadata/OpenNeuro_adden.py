#!/usr/bin/env python3
"""
ds004856 Metadata Integration Script
Merges ds004856 TSV metadata with existing metadata CSV file
"""

import pandas as pd
import sys

# ============================================================================
# CONFIGURATION
# ============================================================================
DS004856_TSV = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/new_hc_data/ds004856/participants.tsv"
EXISTING_CSV = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/complete_metadata_all.csv"
OUTPUT_CSV = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/complete_metadata_with_ds004856.csv"

print("=" * 70)
print("ds004856 METADATA INTEGRATION")
print("=" * 70)

# ============================================================================
# STEP 1: Read ds004856 TSV file
# ============================================================================
print("\n[1/5] Reading ds004856 participants.tsv...")
try:
    ds004856_df = pd.read_csv(DS004856_TSV, sep='\t')
    print(f"  ✓ Loaded {len(ds004856_df)} subjects from TSV")
    print(f"  Columns found: {list(ds004856_df.columns)}")
    print(f"\n  First few rows:")
    print(ds004856_df.head(3).to_string())
except Exception as e:
    print(f"  ✗ Error reading TSV file: {e}")
    sys.exit(1)

# ============================================================================
# STEP 2: Process ds004856 data
# ============================================================================
print("\n[2/5] Processing ds004856 data...")

# Create processed dataframe
ds004856_processed = pd.DataFrame()

# Extract participant_id and create Filename
# participant_id format: "sub-1003" -> Filename: "sub-1003_ses1_1_T1w"
ds004856_processed['participant_id'] = ds004856_df['participant_id']
ds004856_processed['Filename'] = ds004856_processed['participant_id'].apply(
    lambda x: f"{x}_ses1_1_T1w"
)

# Extract Age from AgeMRI_W1 column (use first available age column)
age_columns = ['AgeMRI_W1', 'AgeCog_W1', 'AgePETAmy_W1']
for age_col in age_columns:
    if age_col in ds004856_df.columns:
        ds004856_processed['Age'] = ds004856_df[age_col]
        print(f"  ✓ Using age from column: {age_col}")
        break

# Extract Sex
if 'Sex' in ds004856_df.columns:
    ds004856_processed['Sex_raw'] = ds004856_df['Sex']
    
    # Convert Sex encoding: 'm' -> Male, 'f' -> Female
    sex_map = {'m': 'Male', 'f': 'Female', 'M': 'Male', 'F': 'Female'}
    sex_int_map = {'m': 1.0, 'f': 0.0, 'M': 1.0, 'F': 0.0, 'Male': 1.0, 'Female': 0.0}
    
    ds004856_processed['Sex'] = ds004856_processed['Sex_raw'].map(sex_map)
    ds004856_processed['Sex_Int'] = ds004856_processed['Sex_raw'].map(sex_int_map)
    
    print(f"  ✓ Sex values found: {ds004856_df['Sex'].unique()}")
    print(f"  ✓ Converted to: {ds004856_processed['Sex'].unique()}")
    print(f"  ✓ Sex_Int values: {ds004856_processed['Sex_Int'].unique()}")
else:
    print("  ⚠ Warning: No 'Sex' column found!")
    ds004856_processed['Sex'] = None
    ds004856_processed['Sex_Int'] = None

# Add Diagnosis column (all HC for ds004856)
ds004856_processed['Diagnosis'] = 'HC'

# Add Dataset column
ds004856_processed['Dataset'] = 'ds004856'

# Drop temporary columns
ds004856_processed = ds004856_processed.drop(['participant_id', 'Sex_raw'], axis=1, errors='ignore')

# Reorder columns
ds004856_processed = ds004856_processed[['Filename', 'Dataset', 'Diagnosis', 'Age', 'Sex', 'Sex_Int']]

print(f"\n  ✓ Created {len(ds004856_processed)} entries")
print(f"    Columns: {list(ds004856_processed.columns)}")
print("\n  Example entries:")
print(ds004856_processed.head(3).to_string(index=False))

# Check for missing values
print(f"\n  Missing values:")
print(f"    Age: {ds004856_processed['Age'].isna().sum()}")
print(f"    Sex: {ds004856_processed['Sex'].isna().sum()}")

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

# Add missing columns to ds004856 data (fill with NaN/None)
for col in all_columns:
    if col not in ds004856_processed.columns:
        ds004856_processed[col] = None

# Reorder ds004856 columns to match existing dataset
ds004856_processed = ds004856_processed[all_columns]

# Concatenate datasets
merged_df = pd.concat([existing_df, ds004856_processed], ignore_index=True)

print(f"  ✓ Merged dataset contains {len(merged_df)} total subjects")
print(f"    - Original: {len(existing_df)}")
print(f"    - ds004856: {len(ds004856_processed)}")

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
print(f"  - ds004856 subjects: {len(ds004856_processed)}")

print(f"\nDataset distribution:")
print(merged_df['Dataset'].value_counts().to_string())

print(f"\nDiagnosis distribution:")
print(merged_df['Diagnosis'].value_counts().to_string())

print(f"\nSex distribution:")
print(merged_df['Sex'].value_counts().to_string())

print(f"\nAge statistics (ds004856 only):")
ds004856_ages = merged_df[merged_df['Dataset'] == 'ds004856']['Age']
print(f"  Mean: {ds004856_ages.mean():.1f} years")
print(f"  Median: {ds004856_ages.median():.1f} years")
print(f"  Range: {ds004856_ages.min():.0f} - {ds004856_ages.max():.0f} years")
print(f"  Missing: {ds004856_ages.isna().sum()} subjects")

print(f"\nAge statistics (all data):")
print(f"  Mean: {merged_df['Age'].mean():.1f} years")
print(f"  Range: {merged_df['Age'].min():.0f} - {merged_df['Age'].max():.0f} years")

print("\n" + "=" * 70)
print(f"✓ Output saved to: {OUTPUT_CSV}")
print("=" * 70)

# Show first few rows of ds004856 data in merged dataset
print("\nFirst 3 ds004856 entries in merged dataset:")
ds004856_entries = merged_df[merged_df['Dataset'] == 'ds004856'].head(3)
print(ds004856_entries.to_string(index=False))