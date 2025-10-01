import pathlib
import pandas as pd
import os
import re

# --- Konfiguration ---
RAW_DATA_ROOT = "/net/data.isilon/ag-cherrmann/stumrani/mri_prep"
# Die Kohorten-Ordner liegen unterhalb des RAW_DATA_ROOT, z.B. /mri_prep/mcicnii
COHORT_FOLDERS = ["ixinii", "mcicnii", "cobrenii","NSSnii","NUdatanii","SRBPSnii","whitecatnii"] # Fügen Sie alle Ihre Kohortenordner hinzu
METADATA_PATHS = ["./metadata/test_patients_5.csv"] 
# --------------------

def valid_patients(paths: list) -> list:
    # Liest die Metadaten und gibt eine Liste von Patientennamen zurück
    valid_list = []
    for path in paths: 
        df = pd.read_csv(path) 
        # Gehen Sie davon aus, dass 'Filename' nur den Patienten-ID-Teil enthält, 
        # z.B. 'sub-A00036106' oder den vollen NIfTI-Namen. Wir verwenden hier 
        # den NIfTI-Namen zur maximalen Eindeutigkeit.
        list_of_patients = df['Filename'].tolist() 
        valid_list += list_of_patients
    return valid_list

def get_valid_mri_paths(root_dir: str, cohort_folders: list, metadata_paths: list) -> list:
    
    valid_ids = set(valid_patients(metadata_paths))
    filtered_mri_paths = []

    for cohort_name in cohort_folders:
        cohort_dir = pathlib.Path(root_dir) / cohort_name
        # Sucht alle T1w.nii Dateien in diesem Kohortenordner
        all_mri_paths = list(cohort_dir.glob("*.nii")) 
        
        for mri_path in all_mri_paths:
            mri_filename = mri_path.name
            
            # Prüft, ob ein gültiger ID-Teil im Dateinamen enthalten ist
            if any(valid_id in mri_filename for valid_id in valid_ids):
                filtered_mri_paths.append(str(mri_path))
                
    return filtered_mri_paths

# Beispiel für die Generierung der finalen Liste:
VALID_FILES = get_valid_mri_paths(RAW_DATA_ROOT, COHORT_FOLDERS, METADATA_PATHS)

# Optional: Speichern Sie die Liste in einer Textdatei für den Cluster-Launcher
with open("valid_paths.txt", "w") as f:
    f.write("\n".join(VALID_FILES))