#!/bin/bash
### Job Parameters
#SBATCH --job-name=cat12_batch
#SBATCH --mail-user=lisa.duttenhoefer@stud.uni-heidelberg.de
#SBATCH --mail-type=END,FAIL
#SBATCH --output=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_cat12_%A_%a.out
#SBATCH --error=/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_cat12_%A_%a.err
#SBATCH --time=48:00:00
#SBATCH --partition=single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=12G
#SBATCH --array=1-2
%1-262%50

# Load MATLAB module
module load math/matlab/R2022a

# Define paths
PROJECT_ROOT="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals"
VALID_PATHS_FILE="$PROJECT_ROOT/valid_paths_all_data.txt"
log_path="$PROJECT_ROOT/output/logs"
matlab_script="$PROJECT_ROOT/scripts/run_cat12_full_pipeline.m"
output_root_path="$PROJECT_ROOT/data_output"

# Create directories if they don't exist
mkdir -p "$log_path"
mkdir -p "$output_root_path"

# Calculate total number of subjects and batching parameters
total_subjects=$(wc -l < "$VALID_PATHS_FILE")
batch_size=15  # Process 15 subjects per array job (15 × 2.5h = ~37.5h, safe under 48h limit)
max_array_size=200  # Maximum number of array jobs (3000/15 = 200)

# Check if we have subjects
if [ "$total_subjects" -eq 0 ]; then
    echo "ERROR: No valid subjects found in $VALID_PATHS_FILE"
    exit 1
fi

echo "========================================="
echo "Total subjects to process: $total_subjects"
echo "Batch size: $batch_size subjects per job (~22-25h per job)"
echo "Total jobs needed: $((total_subjects / batch_size + 1))"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Estimated total runtime: ~5 days with 50 parallel jobs"
echo "========================================="

# Calculate start and end indices for this batch
start_index=$(( (SLURM_ARRAY_TASK_ID - 1) * batch_size + 1 ))
end_index=$(( start_index + batch_size - 1 ))

# Ensure end_index doesn't exceed total_subjects
if [ "$end_index" -gt "$total_subjects" ]; then
    end_index=$total_subjects
fi

echo "Processing batch: subjects $start_index to $end_index"

# Read all subjects into array
mapfile -t nifti_files < "$VALID_PATHS_FILE"

# Process files in this batch
for (( i=start_index; i<=end_index; i++ )); do
    # Get array index (0-based)
    array_index=$(( i - 1 ))
    
    # Get subject path
    subject_nifti="${nifti_files[array_index]}"
    
    # Skip if subject is empty
    [ -z "$subject_nifti" ] && continue
    
    # Extract subject name (remove all extensions properly)
    subject_name=$(basename "$subject_nifti")
    subject_name="${subject_name%.nii.gz}"  # Entferne .nii.gz
    subject_name="${subject_name%.nii}"     # Falls nur .nii
    subject_name="${subject_name%.gz}"      # Falls nur .gz
    
    # Define subject-specific output directory
    subject_output_dir="$output_root_path/$subject_name"
    
    echo ""
    echo "========================================="
    echo "Processing subject $i of $total_subjects: $subject_name"
    echo "Input file: $subject_nifti"
    echo "Output directory: $subject_output_dir"
    echo "========================================="
    
    # Create output structure
    mkdir -p "$subject_output_dir"
    
    # Create subject-specific log file
    log_file="$log_path/cat12_${subject_name}.log"
    
    # Check if already processed successfully
    if [ -f "$log_file" ] && grep -q "CAT12 surface analysis and ROI extraction completed successfully" "$log_file"; then
        echo "Subject $subject_name already processed successfully. Skipping."
        continue
    fi
    
    # Check if CSV output already exists
    csv_file="$subject_output_dir/${subject_name}_cat12_results.csv"
    if [ -f "$csv_file" ]; then
        echo "Subject $subject_name CSV already exists. Skipping."
        continue
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
    else
        echo "FAILED: Processing failed for $subject_name"
        echo "Check log: $log_file"
        # Continue with next subject instead of exiting
    fi
done

echo ""
echo "========================================="
echo "Batch $SLURM_ARRAY_TASK_ID completed"
echo "Processed subjects $start_index to $end_index"
echo "========================================="

exit 0