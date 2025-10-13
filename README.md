# CAT12 Batch Processing Pipeline - README

## Overview
This pipeline processes MRI scans using CAT12 (Computational Anatomy Toolbox) for automated brain structure analysis. Processing is performed in parallel using SLURM array jobs on the cluster.
Run on bioquant cluster (appl2 -> login1), with output path to bq_storage (kinit!).

little reminder before you do ANYTHING: change email adress in the .slurm script to your own 
---

## Directory Structure

### Input Files (on isilon)
```
/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/
├── data_output/                                 # SHOULD stay empty for big runs -> output goes to bq-storage (except test runs for better access)
├── metadata/                                    
│   ├── new_files_metadata/                      # original metadata files (unedited) wC, SALD
│   ├── complete_metadata_all.csv                # complete, edited, corrected metadata ALL patients (Filename,Dataset,Diagnosis,Age,Sex,Sex_int,Co_Diagnosis,ICD10_Code,GAF_Score,PANSS_Positive,PANSS_Negative,PANSS_General,PANSS_Total,BPRS_Total,NCRS_Motor,NCRS_Affective,NCRS_Behavioral,NCRS_Total,NSS_Motor,NSS_Total)
│   ├── old_metadata.csv                         # metadata Stand BA (july 2025)
│   ├── metadata_joining.py                      # skript to add new metadata to "complete" file -> needs to be adjusted every time according to new files
│   ├── OpenNeuro_adden.py                       # Script that was used to add OpenNeuro metadata
│   └── SALD_adden.py                            # Script that was used to add SALD metadata
├── new_hc_data/                                 
│   ├── download_openNeuro.sh                    # script to download hc raw MRI images from OpenNeuro using AWS
│   └── download_sald.sh                         # script to download hc raw MRI images from SALD using AWS
├── output/                                      
│   ├── logs/                                    # Log files (SLURM & MATLAB) (ONLY output that stays on bioquant storage for easy access)
│   │   ├── slurm_cat12_<JOBID>_<ARRAYID>.out    # SLURM output (1 per array job) -> tells you which patients are being processed in which job 
│   │   ├── slurm_cat12_<JOBID>_<ARRAYID>.err    # SLURM errors (1 per array job) -> should stay COMPLETELY empty 
│   │   └── cat12_<SUBJECT_NAME>.log             # MATLAB log (1 per subject) (IMPORTANT) -> everything CAT12 does and how long it takes -> take this to control if extraction of all parameters worked
│   └── logs_new_whitecat_4/                     # empty (ignore pls)                  
├── quality_assessment/                          # CAT12_Quality_analysis.py generates basic overview statistics regarding the quality metrics of the processed mri files (!! adjust input files!!) 
│   ├── CAT12_Quality_analysis.py                # generates overview .pngs & problematic_scans.csv -> scans that fail in =>2 categories
├── saving_101025/                               # zwischenstand gesichert für output struktur (unwichtig) 
├── scripts/                                     # MAIN PROCESSING FILES 
│   ├── run_cat12_full_pipeline.m                # MATLAB CAT12 pipeline (ACTIVE)
│   ├── run_cat12_pipeline_batch.slurm           # SLURM batch script (ACTIVE)
│   └── run_cat12_pipeline.slurm                 # SLURM script for test group (-> different valid_paths script)
├── .gitignore                                   
├── config.py                                    # creates the valid_paths.txt lists with all paths to the mri files of the patients we want to process (based on metadata csv) -> looks through stumrani folder & mine
├── README.md                                    # This file
├── valid_paths_all_data.txt                     # List of all ~4000 NIfTI paths (MAIN INPUT) -> all datasets
└── valid_paths.txt                              # test subset (2 random patients) 
```

### Output Files (on bq-storage)

/net/bq-storage/ag-cherrmann/projects/35_BrainMRI/CAT12/
└── data_output/
    └── <SUBJECT_NAME>/                          # 1 folder per subject
        ├── <SUBJECT_NAME>_cat12_results.csv     # MAIN RESULT: All metrics in one row ->  Direct input for statistics/models
        │
        ├── surf/                                # Surface files (FreeSurfer format)
        │   ├── lh.central.<SUBJECT>             # Left central surface (mesh)
        │   ├── rh.central.<SUBJECT>             # Right central surface (mesh)
        │   │                                    # → Needed for: surface-based analysis, visualization
        │   ├── lh.thickness.<SUBJECT>           # Cortical thickness left (per-vertex values)
        │   ├── rh.thickness.<SUBJECT>           # Cortical thickness right (per-vertex values)
        │   │                                    # → Needed for: re-extracting thickness in new ROIs
        │   ├── lh.gyrification.<SUBJECT>        # Gyrification left (per-vertex values)
        │   ├── rh.gyrification.<SUBJECT>        # Gyrification right (per-vertex values)
        │   │                                    # → Needed for: re-extracting gyrification in new ROIs
        │   ├── lh.sphere.<SUBJECT>              # Spherical projection left (for registration)
        │   └── rh.sphere.<SUBJECT>              # Spherical projection right (for registration)
        │                                        # → Needed for: mapping to different atlases
        │
        ├── label/                               # ROI & segmentations
        │   ├── catROI_<SUBJECT>.xml             # Volume ROI data (all atlases)
        │   │                                    # → Contains: Vgm, Vwm, Vcsf for each region
        │   │                                    # → Needed for: re-extracting volume ROIs without reprocessing
        │   ├── catROIs_<SUBJECT>.xml            # Surface ROI data (DK40, Destrieux atlases)
        │   │                                    # → Contains: Thickness, Gyrification for each region
        │   │                                    # → Needed for: re-extracting surface ROIs without reprocessing
        │   └── *.annot                          # FreeSurfer annotations (atlas parcellations)
        │                                        # → Needed for: custom ROI extraction, visualization
        │
        ├── report/                              # Quality control
        │   └── cat_<SUBJECT>.xml                # QC metrics (IQR, NCR, ICR, TIV, all quality measures)
        │                                        # → Needed for: quality filtering, exclusion decisions
        │
        ├── mri/                                 # Segmented volumes (compressed to save space)
        │   ├── p0<SUBJECT>.nii.gz               # Segmentation (GM=1, WM=2, CSF=3)
        │   │                                    # → Needed for: custom volume analysis, lesion masks
        │   ├── p1<SUBJECT>.nii.gz               # GM probability map (0-1 values per voxel)
        │   ├── p2<SUBJECT>.nii.gz               # WM probability map (0-1 values per voxel)
        │   │                                    # → Needed for: partial volume analysis, VBM
        │   ├── mwp1<SUBJECT>.nii.gz             # Modulated normalized GM (in MNI space)
        │   └── mwp2<SUBJECT>.nii.gz             # Modulated normalized WM (in MNI space)
        │                                        # → Needed for: VBM group analysis, re-extracting in MNI atlases
        │
        └── y_<SUBJECT>.nii                      # Forward deformation field (native → MNI)
                                                 # → Needed for: normalizing additional images (fMRI, DTI)
                                                 # → Can be deleted after processing to save ~50MB per subject

---
## Quality Metrics Reference

CAT12 provides comprehensive quality metrics to assess image quality and segmentation accuracy. Understanding these metrics is essential for quality control and data filtering.

### Image Quality Metrics

#### 1. IQR (Image Quality Rating)
- **Definition:** Overall image quality rating as percentage (0-100%)
- **Better is:** HIGHER
- **Interpretation:**
  - 90%+: Excellent (A+)
  - 80-90%: Good (B)
  - 70-80%: Acceptable (C)
  - Below 70%: Problematic (D/F)
- **Use case:** Primary quality filter; exclude subjects below threshold

#### 2. NCR (Noise-to-Contrast Ratio)
- **Definition:** Ratio of image noise to tissue contrast
- **Better is:** LOWER
- **Interpretation:**
  - Below 0.1: Very good image quality
  - 0.1-0.2: Good image quality
  - Above 0.2: High noise levels
- **Use case:** Identify scans with excessive noise

#### 3. ICR (Inhomogeneity-to-Contrast Ratio)
- **Definition:** Ratio of intensity inhomogeneities to tissue contrast
- **Better is:** LOWER
- **Interpretation:**
  - Below 0.1: Very homogeneous
  - 0.1-0.2: Good
  - Above 0.2: Strong field inhomogeneities (bias field issues)
- **Use case:** Detect scans with bias field artifacts

#### 4. Contrast
- **Definition:** Absolute contrast between tissue classes (in intensity units)
- **Better is:** HIGHER
- **Interpretation:**
  - Higher contrast indicates better tissue differentiation
  - Typical range: 100-200 for T1-weighted images
- **Use case:** Assess tissue separability

#### 5. Contrast Ratio (contrastr)
- **Definition:** Normalized contrast (relative to overall intensity)
- **Better is:** HIGHER
- **Interpretation:**
  - Similar to Contrast but normalized
  - Typical range: 0.2-0.4
- **Use case:** Compare contrast across different scanners/protocols

### Surface Quality Metrics

#### 6. Surface Euler Number
- **Definition:** Topological characteristic of reconstructed brain surface (Euler characteristic)
- **Better is:** HIGHER (closer to 2 for perfect sphere)
- **Interpretation:**
  - Ideal: approximately 2 (closed surface without holes)
  - Lower values indicate topological defects (holes, handles)
  - Negative values indicate many topological errors
- **Use case:** Identify surfaces with topological defects

#### 7. Surface Defect Area
- **Definition:** Percentage of surface with topological defects
- **Better is:** LOWER
- **Interpretation:**
  - Below 0.1%: Very good
  - 0.1-0.5%: Good
  - Above 0.5%: Problematic
- **Use case:** Quantify extent of surface defects

#### 8. Surface Defect Number
- **Definition:** Number of topological defects on the surface
- **Better is:** LOWER
- **Interpretation:**
  - 0-5: Very good
  - 5-10: Acceptable
  - Above 10: Problematic
- **Use case:** Count discrete surface errors

#### 9. Surface Intensity RMSE
- **Definition:** Root Mean Square Error of intensity values at tissue boundaries
- **Better is:** LOWER
- **Interpretation:**
  - Measures how well segmentation boundaries match expected intensity values
  - Higher values indicate poorer boundary detection
- **Use case:** Assess segmentation accuracy at boundaries

#### 10. Surface Position RMSE
- **Definition:** Root Mean Square Error of surface positioning
- **Better is:** LOWER
- **Interpretation:**
  - Measures spatial accuracy of surface reconstruction
  - Higher values indicate less precise positioning
- **Use case:** Evaluate geometric accuracy of surfaces

#### 11. SIQR (Surface IQR)
- **Definition:** Specific quality rating for surface reconstruction
- **Better is:** HIGHER
- **Interpretation:**
  - Combines various surface metrics
  - Similar scale to IQR
- **Use case:** Overall surface quality assessment

### Anatomical Measurements (Not Quality Metrics)

#### 12. vol_TIV (Total Intracranial Volume)
- **Definition:** Total intracranial volume in cm³ (brain + CSF)
- **Better is:** Neutral (anatomical measurement, not quality)
- **Interpretation:**
  - Typical range: 1200-1600 cm³ (adults)
  - Used for normalization of other volumes
- **Use case:** Normalize regional volumes, control for head size

#### 13. surf_TSA (Total Surface Area)
- **Definition:** Total brain surface area in cm²
- **Better is:** Neutral (anatomical measurement, not quality)
- **Interpretation:**
  - Typical range: 1500-2000 cm² (adults)
  - Correlates with brain folding and volume
- **Use case:** Assess cortical surface extent

### Current Quality Control Pipeline in CAT12_Quality_analysis.py -> problematic_scans.py
1. **Primary filter (strict):**
   - IQR greater than 80%
   - NCR less than 0.15
   - ICR less than 0.15

2. **Surface quality filter:**
   - Surface Euler Number greater than 0
   - Surface Defect Area less than 0.5%
   - Surface Defect Number less than 10

## CSV Output Structure (`<SUBJECT>_cat12_results.csv`)

The CSV file contains approximately 1500+ columns with all extracted metrics:

### 1. Quality Measures - whole brain
- `IQR` - Image Quality Rating (A+/A/B+/B/C+/C)
- `NCR` - Noise-to-Contrast Ratio
- `ICR` - Inhomogeneity-to-Contrast Ratio
- `res_RMS` - Root Mean Square Resolution

### 2. Global Volume Measures - whole brain
- `TIV` - Total Intracranial Volume (mm³) IMPORTANT -> maybe normalization?
- `GM_vol` - Gray Matter Volume (mm³)
- `WM_vol` - White Matter Volume (mm³)
- `CSF_vol` - Cerebrospinal Fluid Volume (mm³)
- `WMH_vol` - White Matter Hyperintensities Volume (mm³)

### 3. Global Cortical Measures - whole brain
- `mean_thickness_lh` - Mean cortical thickness left hemisphere (mm)
- `mean_thickness_rh` - Mean cortical thickness right hemisphere (mm)
- `mean_thickness_global` - Mean global cortical thickness (mm)
- `mean_gyri_lh` - Mean gyrification left hemisphere
- `mean_gyri_rh` - Mean gyrification right hemisphere
- `mean_gyri_global` - Mean global gyrification

### 4. Volume-Based ROI Data (per atlas & region)
For each atlas, measurements are provided for different tissue types:

**Format:** `V[gm/wm/csf]_<ATLAS>_<REGION_NAME>`

**Atlases:**
(x3: Vgm & Vwm & Vcsf)
(x2: Vgm & Vwm)
(x1: Vgm )
- `Neurom_*` - Neuromorphometrics Atlas (136 regions x3)
- `lpba40_*` - LONI Probabilistic Brain Atlas (56 regions x2)
- `cobra_*` - COBRA Atlas (52 regions x2)
- `SUIT_*` - SUIT Cerebellar Atlas (28 regions x2)
- `IBSR_*` - Internet Brain Segmentation Repository (48 regions x2)
- `AAL3_*` - Automated Anatomical Labeling 3 (170 regions x1)
- `Schaefer100_*` - Schaefer 100 Parcels (100 regions x2)
- `Schaefer200_*` - Schaefer 200 Parcels (200 regions x2)

### 5. Surface-Based ROI Data (per atlas & region)
**Format:** `[T/G]_<ATLAS>_<REGION_NAME>`

**T = Thickness (cortical thickness), G = Gyrification**

**Atlases:**
- `DK40_*` - Desikan-Killiany Atlas (68 cortical regions)
- `Destrieux_*` - Destrieux Atlas (148 cortical regions)

---

## Pipeline Workflow

### 1. Job Submission
```bash
sbatch run_cat12_pipeline_batch.slurm
```

**Parameters:**
- 3923 subjects total (ixi, epsy, cobre, srpbs, mcic, nu, sald, openneuro, whiteCAT, nss)
- 267 array jobs (15 subjects each)
- Max. 80 jobs in parallel (`%80`)
- 48h time limit per job
- 12 GB RAM per job
-> wenn man alles so lässt passt es für das cluster 

### 2. Per Array Job
Each job processes 15 subjects sequentially:

```
Job 1:   Subjects 1-15
Job 2:   Subjects 16-30
...
Job 267: Subjects 3991-4000
```

### 3. Per Subject (MATLAB Pipeline)

#### A. CAT12 Segmentation
- Tissue segmentation (GM, WM, CSF)
- Surface reconstruction (lh/rh central, sphere, pial)
- Normalization to MNI space
- Volume-based ROI extraction (right now 8 atlases)

#### B. Surface Extraction
- Cortical thickness
- Gyrification Index
- Sulcus depth (optional) -> not rn

#### C. Surface ROI Extraction
- DK40 Atlas (Desikan-Killiany)
- Destrieux Atlas (aparc_a2009s)
- Thickness & gyrification per region

#### D. Data Aggregation
- Aggregate all metrics into 1 CSV
- Extract quality measures from XML
- Calculate global & regional values

#### E. Cleanup
- Delete inverse deformation fields
- Compress volumes (.nii → .nii.gz)
- Keep surfaces & CSVs

**Duration per subject:** approximately 1h 40min  
**Storage per subject:** approximately 200-250 MB

---

## Monitoring & Troubleshooting

### Monitor Jobs
```bash
# Number of running jobs
squeue -u lduttenhoefer | wc -l

# View job details
squeue -u lduttenhoefer -o "%.18i %.9P %.30j %.8T %.10M %.6D"

# Cancel a single job
scancel <JOB_ID>

# Cancel all jobs
scancel -u lduttenhoefer
```

### Check Progress
-> wenn auf bioquant -> /net/bq-storage/
-> wenn auf curry -> /media/bq-storage/

```bash
# Number of completed subjects (CSV files)
find /media/bq-storage/ag-cherrmann/projects/35_BrainMRI/CAT12/data_output/ -name "*_cat12_results.csv" | wc -l

# Number of output folders
ls /media/bq-storage/ag-cherrmann/projects/35_BrainMRI/CAT12/data_output/ | wc -l

# Storage usage
du -sh /media/bq-storage/ag-cherrmann/projects/35_BrainMRI/CAT12/data_output/
```

### Analyze Logs
```bash
# Live log of a running job
tail -f /net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/slurm_cat12_*_1.out

# MATLAB log of a subject
less /net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/cat12_<SUBJECT_NAME>.log

# Find successful subjects
grep -l "completed successfully" /net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/cat12_*.log | wc -l

# Find failed subjects
grep -L "completed successfully" /net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/output/logs/cat12_*.log
```
## Re-Processing Individual Subjects

If individual subjects fail:

```bash
# Find failed subjects
comm -23 \
  <(cat valid_paths_all_data.txt | xargs -n1 basename | sed 's/.nii.gz$//' | sed 's/.nii$//' | sort) \
  <(ls /media/bq-storage/ag-cherrmann/projects/35_BrainMRI/CAT12/data_output/ | sort) \
  > failed_subjects.txt

# Create new input list
# (Add full paths again)

# Start re-processing with adjusted array size
```

The pipeline automatically skips subjects that already have a CSV file.

---

## Email Notifications
(PLEASE change EMAIL-ADRESS from mine to urs if u copy the code!! )
Configured with `#SBATCH --mail-type=FAIL`:
- Only for job failures (timeout, OOM, crash)
- Not for successful completion
- Not when individual subjects fail within a job

With 267 jobs, ideally 0 emails.

#SBATCH --mail-type=FAIL,END -> DO NOT do this for the big run! you will end up with 260 emails

**For questions:**
- Lisa Duttenhöfer: lisa.duttenhoefer@stud.uni-heidelberg.de
