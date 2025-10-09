#!/bin/bash
### Job Parameters
#SBATCH --job-name=cat12_full_pipeline
#SBATCH --mail-user=lisa.duttenhoefer@stud.uni-heidelberg.de
#SBATCH --mail-type=END,FAIL
#SBATCH --output=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_cat12_%A_%a.out
#SBATCH --error=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_cat12_%A_%a.err
#SBATCH --time=48:00:00
#SBATCH --partition=single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --array=1-10

# Load MATLAB module
module load math/matlab/R2022a

# Define paths - ALLES IN DEINEM ORDNER
PROJECT_ROOT="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals"
VALID_PATHS_FILE="$PROJECT_ROOT/valid_paths.txt"
log_path="$PROJECT_ROOT/output/logs"
matlab_script="$PROJECT_ROOT/scripts/run_cat12_full_pipeline.m"
output_root_path="$PROJECT_ROOT/data_output"

# Create directories if they don't exist
mkdir -p "$log_path"
mkdir -p "$output_root_path"

# Read list of input .nii files
mapfile -t nifti_files < "$VALID_PATHS_FILE"

total_subjects=${#nifti_files[@]}

# Check if we have subjects
if [ "$total_subjects" -eq 0 ]; then
    echo "ERROR: No valid subjects found in $VALID_PATHS_FILE"
    exit 1
fi

# Get the subject for this array task
task_index=$((SLURM_ARRAY_TASK_ID - 1))

if [ "$task_index" -ge "$total_subjects" ] || [ "$task_index" -lt 0 ]; then
    echo "ERROR: SLURM_ARRAY_TASK_ID $SLURM_ARRAY_TASK_ID out of range (1 to $total_subjects)"
    exit 1
fi

# Select the subject
subject_nifti="${nifti_files[task_index]}"

# Extract subject name
subject_name=$(basename "$subject_nifti" .nii)

# Define subject-specific output directory
subject_output_dir="$output_root_path/$subject_name"

echo "========================================="
echo "Processing subject: $subject_name"
echo "Task ID: $SLURM_ARRAY_TASK_ID"
echo "Input file: $subject_nifti"
echo "Output directory: $subject_output_dir"
echo "========================================="

# Create output structure
mkdir -p "$subject_output_dir"

# Create subject-specific log file
log_file="$log_path/cat12_${subject_name}.log"

# Check if already processed
if [ -f "$log_file" ] && grep -q "CAT12 surface analysis and ROI extraction completed successfully" "$log_file"; then
    echo "Subject $subject_name already processed successfully. Skipping."
    exit 0
fi

# Set environment variables for MATLAB
export SUBJECT_PATH="$subject_nifti"
export OUTPUT_ROOT="$subject_output_dir"

# Run MATLAB script
echo "Starting CAT12 processing..."
matlab -nodisplay -nosplash -nodesktop -r "run('$matlab_script'); exit;" > "$log_file" 2>&1

# Check if successful
if grep -q "CAT12 surface analysis and ROI extraction completed successfully" "$log_file"; then
    echo "SUCCESS: Processing completed for $subject_name"
    exit 0
else
    echo "FAILED: Processing failed for $subject_name"
    echo "Check log: $log_file"
    exit 1
fi