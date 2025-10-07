import pathlib
import pandas as pd
import os
from collections import Counter

# --- Konfiguration ---
RAW_DATA_ROOT = "/net/data.isilon/ag-cherrmann/stumrani/mri_prep"

# PRIORITÄT 1: Primäre Ordner (keine Duplikate)
PRIMARY_COHORT_FOLDERS = [
    "ixinii",
    "mcicnii",
    "cobrenii",
    "SRBPSnii",
    "earlypsyconii",
    "NSSnii",
    "NUdatanii",
    "whitecatnii",
    "whiteCAT_updt"
]

# PRIORITÄT 2: Sekundäre Ordner (nur für fehlende Patienten)
SECONDARY_COHORT_FOLDERS = [
    "mcicprocessednii",
    "cobreprocessednii",
    "nsscat12_updt",
    "nsscat12",
    "nss_updt",
    "NUdataniip",
    "whitecat12_pupdt",
    "whitecat"
]

# PRIORITÄT 3: Zusätzliche externe Pfade
ADDITIONAL_SEARCH_PATHS = [
    "/net/data.isilon/ag-cherrmann/flam/cat12/data/all_whitecat_gm_nii"
]

# ANGEPASST: Pfad zu deinen Metadaten
METADATA_PATHS = ["/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/complete_metadata.csv"]
# Output-Pfad für valid_paths.txt
OUTPUT_FILE = "/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/valid_paths_all_data.txt"
# --------------------

def check_duplicates_in_metadata(paths: list):
    """
    Prüft auf Duplikate in den Metadaten
    """
    print("\n=== Duplikatsprüfung in Metadaten ===")
    all_patients = []
    
    for path in paths:
        if not os.path.exists(path):
            continue
        df = pd.read_csv(path)
        if 'Filename' not in df.columns:
            continue
        all_patients.extend(df['Filename'].tolist())
    
    # Zähle Vorkommen jedes Patienten
    patient_counts = Counter(all_patients)
    duplicates = {patient: count for patient, count in patient_counts.items() if count > 1}
    
    if duplicates:
        print(f"⚠️  WARNUNG: {len(duplicates)} Duplikate in Metadaten gefunden:")
        for patient, count in sorted(duplicates.items()):
            print(f"  - {patient}: {count}x vorhanden")
        return duplicates
    else:
        print("✓ Keine Duplikate in Metadaten gefunden")
        return {}

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

def get_valid_mri_paths(root_dir: str, primary_folders: list, secondary_folders: list, additional_paths: list, metadata_paths: list) -> tuple:
    """
    Findet alle .nii Dateien in drei Phasen:
    1. PHASE 1: Suche in PRIMARY folders
    2. PHASE 2: Suche in SECONDARY folders nur für noch fehlende Patienten
    3. PHASE 3: Suche in ADDITIONAL paths nur für noch fehlende Patienten
    Gibt (filtered_paths, duplicate_info, found_patients) zurück
    """
    all_valid_ids = set(valid_patients(metadata_paths))
    filtered_mri_paths = []
    patient_file_mapping = {}
    found_patients = set()
    
    print("\n" + "="*60)
    print("PHASE 1: Suche in PRIMÄREN Ordnern")
    print("="*60)
    
    # PHASE 1: Primäre Ordner durchsuchen
    for cohort_name in primary_folders:
        cohort_dir = pathlib.Path(root_dir) / cohort_name
        if not cohort_dir.exists():
            print(f"WARNING: Cohort directory not found: {cohort_dir}")
            continue
        
        all_mri_paths = list(cohort_dir.glob("*.nii"))
        print(f"Scanning {cohort_name}: {len(all_mri_paths)} .nii files")
        
        for mri_path in all_mri_paths:
            mri_filename = mri_path.name
            for valid_id in all_valid_ids:
                if valid_id in mri_filename and valid_id not in found_patients:
                    filtered_mri_paths.append(str(mri_path))
                    found_patients.add(valid_id)
                    
                    if valid_id not in patient_file_mapping:
                        patient_file_mapping[valid_id] = []
                    patient_file_mapping[valid_id].append(str(mri_path))
                    break
    
    print(f"\n✓ Phase 1 abgeschlossen: {len(found_patients)} Patienten gefunden")
    
    # Identifiziere fehlende Patienten
    missing_patients = all_valid_ids - found_patients
    
    if missing_patients:
        print(f"\n⚠️  {len(missing_patients)} Patienten noch nicht gefunden")
        print("\n" + "="*60)
        print("PHASE 2: Suche in SEKUNDÄREN Ordnern für fehlende Patienten")
        print("="*60)
        
        # PHASE 2: Sekundäre Ordner nur für fehlende Patienten
        for cohort_name in secondary_folders:
            if not missing_patients:
                break
                
            cohort_dir = pathlib.Path(root_dir) / cohort_name
            if not cohort_dir.exists():
                print(f"WARNING: Cohort directory not found: {cohort_dir}")
                continue
            
            all_mri_paths = list(cohort_dir.glob("*.nii"))
            print(f"Scanning {cohort_name}: {len(all_mri_paths)} .nii files")
            
            found_in_this_cohort = 0
            for mri_path in all_mri_paths:
                mri_filename = mri_path.name
                for valid_id in list(missing_patients):
                    if valid_id in mri_filename:
                        filtered_mri_paths.append(str(mri_path))
                        found_patients.add(valid_id)
                        missing_patients.remove(valid_id)
                        found_in_this_cohort += 1
                        
                        if valid_id not in patient_file_mapping:
                            patient_file_mapping[valid_id] = []
                        patient_file_mapping[valid_id].append(str(mri_path))
                        break
            
            if found_in_this_cohort > 0:
                print(f"  → {found_in_this_cohort} fehlende Patienten gefunden")
        
        print(f"\n✓ Phase 2 abgeschlossen: Insgesamt {len(found_patients)} Patienten gefunden")
    else:
        print("\n✓ Alle Patienten in primären Ordnern gefunden - Phase 2 nicht nötig")
    
    # PHASE 3: Zusätzliche Pfade durchsuchen
    missing_patients = all_valid_ids - found_patients
    
    if missing_patients and additional_paths:
        print(f"\n⚠️  {len(missing_patients)} Patienten noch immer nicht gefunden")
        print("\n" + "="*60)
        print("PHASE 3: Suche in ZUSÄTZLICHEN Pfaden für fehlende Patienten")
        print("="*60)
        
        for additional_path in additional_paths:
            if not missing_patients:
                break
                
            additional_dir = pathlib.Path(additional_path)
            if not additional_dir.exists():
                print(f"WARNING: Additional path not found: {additional_path}")
                continue
            
            all_mri_paths = list(additional_dir.glob("*.nii"))
            print(f"Scanning {additional_dir.name}: {len(all_mri_paths)} .nii files")
            
            found_in_this_path = 0
            for mri_path in all_mri_paths:
                mri_filename = mri_path.name
                for valid_id in list(missing_patients):
                    if valid_id in mri_filename:
                        filtered_mri_paths.append(str(mri_path))
                        found_patients.add(valid_id)
                        missing_patients.remove(valid_id)
                        found_in_this_path += 1
                        
                        if valid_id not in patient_file_mapping:
                            patient_file_mapping[valid_id] = []
                        patient_file_mapping[valid_id].append(str(mri_path))
                        break
            
            if found_in_this_path > 0:
                print(f"  → {found_in_this_path} fehlende Patienten gefunden")
        
        print(f"\n✓ Phase 3 abgeschlossen: Insgesamt {len(found_patients)} Patienten gefunden")
    
    # Prüfe auf mehrere Dateien pro Patient (sollte nicht vorkommen)
    print("\n=== Duplikatsprüfung bei MRI-Dateien ===")
    file_duplicates = {patient: files for patient, files in patient_file_mapping.items() if len(files) > 1}
    
    if file_duplicates:
        print(f"⚠️  WARNUNG: {len(file_duplicates)} Patienten haben mehrere MRI-Dateien:")
        for patient, files in sorted(file_duplicates.items()):
            print(f"\n  Patient: {patient} ({len(files)} Dateien)")
            for f in files:
                print(f"    - {f}")
    else:
        print("✓ Keine Duplikate bei MRI-Dateien gefunden")
    
    # Zeige finale fehlende Patienten
    final_missing = all_valid_ids - found_patients
    if final_missing:
        print(f"\n⚠️  WARNUNG: {len(final_missing)} Patienten nicht gefunden:")
        for patient in sorted(list(final_missing))[:20]:  # Zeige max 20
            print(f"  - {patient}")
        if len(final_missing) > 20:
            print(f"  ... und {len(final_missing) - 20} weitere")
    
    print(f"\nTotal matched files: {len(filtered_mri_paths)}")
    return filtered_mri_paths, file_duplicates

if __name__ == "__main__":
    # Generiere die finale Liste
    print("=== Starting file validation ===")
    
    # Prüfe zuerst Duplikate in Metadaten
    metadata_duplicates = check_duplicates_in_metadata(METADATA_PATHS)
    
    # Finde und prüfe MRI-Dateien mit 3-Phasen Ansatz
    VALID_FILES, file_duplicates = get_valid_mri_paths(
        RAW_DATA_ROOT, 
        PRIMARY_COHORT_FOLDERS, 
        SECONDARY_COHORT_FOLDERS,
        ADDITIONAL_SEARCH_PATHS,
        METADATA_PATHS
    )
    
    if len(VALID_FILES) == 0:
        print("\nERROR: No valid files found! Check your metadata and cohort folders.")
        exit(1)
    
    # Speichere die Liste in einer Textdatei für SLURM
    with open(OUTPUT_FILE, "w") as f:
        f.write("\n".join(VALID_FILES))
    
    print(f"\n=== Validation complete ===")
    print(f"Valid paths saved to: {OUTPUT_FILE}")
    print(f"Total files to process: {len(VALID_FILES)}")
    
    # Zusammenfassung
    print("\n=== ZUSAMMENFASSUNG ===")
    if metadata_duplicates:
        print(f"⚠️  Metadaten-Duplikate: {len(metadata_duplicates)}")
    else:
        print("✓ Metadaten: Keine Duplikate")
    
    if file_duplicates:
        print(f"⚠️  MRI-Datei-Duplikate: {len(file_duplicates)} Patienten mit mehreren Dateien")
    else:
        print("✓ MRI-Dateien: Keine Duplikate")