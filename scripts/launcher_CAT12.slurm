#!/bin/bash
### Job Parameters
#SBATCH --job-name=cat12_post_segmentation
#SBATCH --mail-user=lisa.duttenhoefer@stud.uni-heidelberg.de

#SBATCH --output=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_post_seg_%A_%a.out
#SBATCH --error=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_post_seg_%A_%a.err
#SBATCH --time=48:00:00
#SBATCH --partition=single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
# WICHTIG: Setzen Sie dies auf die Gesamtzahl der Einträge in valid_paths.txt.
# Beispiel: Wenn valid_paths.txt 5 Einträge hat:
#SBATCH --array=1-5 

# Load MATLAB module
module load math/matlab/R2022a

# Define paths
# ----------------------------------------------------------------------
# INPUT PFADE
VALID_PATHS_FILE="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/valid_paths.txt"
# OUTPUT PFADE
log_path="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs"
matlab_script="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/scripts/run_cat12_jobs.m"
output_root_path="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/data_output"
# ----------------------------------------------------------------------

# Create log and output directories if they don't exist
mkdir -p "$log_path"
mkdir -p "$output_root_path"

# ----------------------------------------------------------------------
# LOGIK: Lese Pfade und konvertiere NIFTI-Pfade in CAT12-Thickness-Pfade
# ----------------------------------------------------------------------
# Lese die Liste der NIFTI-Dateien (z.B. .../IXI170-Guys-0843-T1.nii)
mapfile -t nifti_files < "$VALID_PATHS_FILE"

# Array für die tatsächlichen thickness-Pfade
thickness_files=()

# Führe die Transformation durch
for nifti_file in "${nifti_files[@]}"; do
    if [ -z "$nifti_file" ]; then continue; fi # Überspringe leere Zeilen

    # 1. Extrahiere den Basisnamen der NIFTI-Datei (z.B. IXI170-Guys-0843-T1)
    nifti_basename=$(basename "$nifti_file" .nii)
    
    # 2. Bestimme den übergeordneten Ordner des NIFTI-Files (z.B. /.../ixinii/)
    cat_output_root=$(dirname "$nifti_file") 
    
    # 3. Konstruiere den erwarteten Pfad zur lh.thickness-Datei
    thickness_file="${cat_output_root}/surf/lh.thickness.${nifti_basename}"
    thickness_files+=("$thickness_file")
done

total_subjects=${#thickness_files[@]}

# ----------------------------------------------------------------------
# Array Job Steuerung
# ----------------------------------------------------------------------

# FEHLERBEHEBUNG FÜR GANZZAHL-AUSDRUCK:
# Stellen Sie sicher, dass total_subjects > 0 ist, bevor Sie fortfahren
if [ "$total_subjects" -eq 0 ]; then
    echo "FEHLER: Keine gültigen Subjekte in valid_paths.txt gefunden oder die Pfadtransformation ist fehlgeschlagen."
    echo "Bitte valid_paths.txt überprüfen. Wird beendet."
    exit 1
fi

# NEUE ARRAY-LOGIK: Jeder Task verarbeitet EINEN eindeutigen Patienten
# Wir setzen task_index = SLURM_ARRAY_TASK_ID. Da Arrays bei 0 beginnen, 
# müssen wir 1 abziehen, um den korrekten Array-Index zu erhalten.
task_index=$((SLURM_ARRAY_TASK_ID - 1))

# Prüfen, ob der Index gültig ist
if [ "$task_index" -ge "$total_subjects" ] || [ "$task_index" -lt 0 ]; then
    echo "FEHLER: SLURM_ARRAY_TASK_ID $SLURM_ARRAY_TASK_ID liegt außerhalb des gültigen Bereichs (1 bis $total_subjects). Wird beendet."
    exit 1
fi

# ----------------------------------------------------------------------
# Verarbeitung des EINZELNEN Subjekts durch den Task
# ----------------------------------------------------------------------

# Wähle den Patienten basierend auf dem korrigierten Index aus
subject_thickness_file="${thickness_files[task_index]}"
    
# Extract subject name aus dem thickness-Pfad
thickness_basename=$(basename "$subject_thickness_file")
subject_name=$(echo "$thickness_basename" | sed 's/lh.thickness\.//')
    
# Definiere den spezifischen Output-Ordner für dieses Subjekt im ZIEL-Pfad
subject_output_dir="$output_root_path/$subject_name"
    
echo "Processing subject: $subject_name (Task ID $SLURM_ARRAY_TASK_ID)"
    
# Create required output structure in target path (Falls nicht schon geschehen)
mkdir -p "$subject_output_dir/surf"
mkdir -p "$subject_output_dir/report"

# Create subject-specific log file
    log_file="$log_path/post_seg_${subject_name}.log"
    
    # Check if subject has already been successfully processed
    if [ -f "$log_file" ] && grep -q "CAT12 surface analysis and ROI extraction completed successfully" "$log_file"; then
        echo "Subject $subject_name has already been successfully processed. Skipping."
        exit 0 # Erfolgreich beenden, da bereits fertig
    fi
    
# Set environment variables for MATLAB script
export SUBJECT_PATH="$subject_thickness_file"
export OUTPUT_ROOT="$subject_output_dir"
    
echo "Starting post-segmentation processing..."
echo "INPUT thickness file: $subject_thickness_file"
echo "OUTPUT target folder: $subject_output_dir"
    
# Run MATLAB script for a single subject
matlab -nodisplay -nosplash -nodesktop -r "run('$matlab_script'); exit;" > "$log_file" 2>&1
    
# Check if processing was successful (durch Lesen des logs)
if grep -q "CAT12 surface analysis and ROI extraction completed successfully" "$log_file"; then
    echo "Processing completed successfully for subject: $subject_name"
    exit 0
else
    echo "Processing FAILED for subject: $subject_name"
    echo "Check log file: $log_file"
    exit 1
fi

# Die ursprüngliche End-of-Stage-Logik wird nicht mehr benötigt, da jeder Task
# nur EINEN Patienten verarbeitet und dann endet.