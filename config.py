import pathlib
import pandas as pd
import os

# --- Konfiguration ---
RAW_DATA_ROOT = "/net/data.isilon/ag-cherrmann/stumrani/mri_prep"

# Die Kohorten-Ordner liegen unterhalb des RAW_DATA_ROOT
COHORT_FOLDERS = ["ixinii", "mcicnii", "cobrenii", "NSSnii", "NUdatanii", "SRBPSnii", "whitecatnii"]

# ANGEPASST: Pfad zu deinen Metadaten
METADATA_PATHS = ["/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/test_patients_5.csv"]

# Output-Pfad für valid_paths.txt
OUTPUT_FILE = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/valid_paths.txt"
# --------------------

def valid_patients(paths: list) -> list:
    """
    Liest die Metadaten und gibt eine Liste von Patientennamen zurück
    """
    valid_list = []
    for path in paths:
        if not os.path.exists(path):
            print(f"WARNING: Metadata file not found: {path}")
            continue
            
        df = pd.read_csv(path)
        
        # Annahme: 'Filename' enthält den Patientenidentifikator
        if 'Filename' not in df.columns:
            print(f"WARNING: 'Filename' column not found in {path}")
            continue
            
        list_of_patients = df['Filename'].tolist()
        valid_list += list_of_patients
        
    print(f"Found {len(valid_list)} valid patient IDs from metadata")
    return valid_list

def get_valid_mri_paths(root_dir: str, cohort_folders: list, metadata_paths: list) -> list:
    """
    Findet alle .nii Dateien, die zu den Patienten in den Metadaten gehören
    """
    valid_ids = set(valid_patients(metadata_paths))
    filtered_mri_paths = []
    
    for cohort_name in cohort_folders:
        cohort_dir = pathlib.Path(root_dir) / cohort_name
        
        if not cohort_dir.exists():
            print(f"WARNING: Cohort directory not found: {cohort_dir}")
            continue
        
        # Sucht alle .nii Dateien in diesem Kohortenordner
        all_mri_paths = list(cohort_dir.glob("*.nii"))
        print(f"Found {len(all_mri_paths)} .nii files in {cohort_name}")
        
        for mri_path in all_mri_paths:
            mri_filename = mri_path.name
            
            # Prüft, ob ein gültiger ID-Teil im Dateinamen enthalten ist
            if any(valid_id in mri_filename for valid_id in valid_ids):
                filtered_mri_paths.append(str(mri_path))
    
    print(f"\nTotal matched files: {len(filtered_mri_paths)}")
    return filtered_mri_paths

if __name__ == "__main__":
    # Generiere die finale Liste
    print("=== Starting file validation ===")
    VALID_FILES = get_valid_mri_paths(RAW_DATA_ROOT, COHORT_FOLDERS, METADATA_PATHS)
    
    if len(VALID_FILES) == 0:
        print("\nERROR: No valid files found! Check your metadata and cohort folders.")
        exit(1)
    
    # Speichere die Liste in einer Textdatei für SLURM
    with open(OUTPUT_FILE, "w") as f:
        f.write("\n".join(VALID_FILES))
    
    print(f"\n=== Validation complete ===")
    print(f"Valid paths saved to: {OUTPUT_FILE}")
    print(f"Total files to process: {len(VALID_FILES)}")