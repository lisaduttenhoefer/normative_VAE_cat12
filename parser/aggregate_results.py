import pathlib
import pandas as pd
import os

# --- Configuration (Adjust if needed) ---
RAW_DATA_DIR = "/net/data.isilon/ag-cherrmann/stumrani/mri_prep"
EXTRACTED_H5_DIR = "/net/data.isilon/ag-cherrmann/nschmidt/project/final_data" 
# ----------------------------------------

def aggregate_cat12_roi_data(root_dir: str, output_h5_path: str):
    
    # 1. Find all final ROI CSV files across all subject folders
    # We look for the general volumetric/TIV CSV which should contain all volume ROIs.
    # CAT12 usually saves surface data in a separate, but similarly named, CSV. 
    
    # You may need to adapt this search pattern based on the exact CAT12 output filenames!
    vol_csv_paths = list(pathlib.Path(root_dir).rglob("report/cat_vol_TIV_*.csv"))
    
    if not vol_csv_paths:
        print("No CAT12 ROI CSV files found. Check your file path and run_cat12_jobs.m output.")
        return

    all_subjects_dfs = []

    for csv_path in vol_csv_paths:
        try:
            # 2. Read the CSV (ROI names are in the index)
            df = pd.read_csv(csv_path, index_col=0)
            
            # 3. Extract the Subject ID for the column/row index
            # Example: Extracts 'sub-whiteCAT001_ses-01_T1w' from the file path/name
            subject_id = re.search(r"cat_vol_TIV_(.*).csv", os.path.basename(csv_path)).group(1)
            
            # 4. Transpose to get ROIs/Measures as columns and Subject as index/row
            df_T = df.T 
            df_T.index = [subject_id] # Set the index to the subject ID
            
            all_subjects_dfs.append(df_T)
        
        except Exception as e:
            print(f"Skipping file {csv_path} due to error: {e}")
            continue

    # 5. Concatenate all subject dataframes vertically (subjects as rows)
    final_df = pd.concat(all_subjects_dfs, axis=0)
    
    # 6. Save the final aggregated data (Transposed version for your VAE)
    final_df.to_hdf(output_h5_path, key='final_roi_data', mode='w')
    print(f"\nSuccessfully aggregated and saved {len(final_df)} subjects to {output_h5_path}")

# Run the aggregation
aggregate_cat12_roi_data(RAW_DATA_DIR, fullfile(EXTRACTED_H5_DIR, 'final_roi_data.h5'))