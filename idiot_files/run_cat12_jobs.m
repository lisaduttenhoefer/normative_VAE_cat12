% CAT12 Complete Post-Segmentation Processing Script
% Extracts all ROI values into ONE combined CSV file
% - Volume ROI values (GM, WM, CSF) from 6 atlases
% - Surface ROI values (Thickness, Gyrification) from 2 atlases
% Output: Single wide-format CSV with all metrics as columns

% Set the paths to your SPM and CAT12 installations
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12');
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12');

spm('defaults', 'FMRI');
spm_jobman('initcfg');

% ----------------------------------------------------------------
% Path Definition from Environment Variables
% ----------------------------------------------------------------
subject_path = getenv('SUBJECT_PATH'); 
output_root_path = getenv('OUTPUT_ROOT'); 

if isempty(subject_path)
    error('SUBJECT_PATH environment variable is not defined.');
end
if isempty(output_root_path)
    error('OUTPUT_ROOT environment variable is not defined.');
end

% --- Extract Subject Name ---
if ispc
    parts = strsplit(subject_path, '\');
else
    parts = strsplit(subject_path, '/');
end
filename_full = parts{end};

fprintf('DEBUG: Full filename extracted = %s\n', filename_full);
subj_name = strrep(filename_full, 'lh.thickness.', '');

fprintf('DEBUG: Subject name after prefix removal = %s\n', subj_name);

if isempty(subj_name) || strcmp(subj_name, 'lh') || strcmp(subj_name, 'rh') || strcmp(subj_name, 'lh.thickness')
    error('ERROR: Invalid Subject Name extracted: %s (Original: %s)', subj_name, subject_path);
end

fprintf('DEBUG: subject_path (INPUT) = %s\n', subject_path);
fprintf('DEBUG: output_root_path (TARGET) = %s\n', output_root_path);
fprintf('DEBUG: subj_name = %s\n', subj_name);
fprintf('Processing complete ROI extraction for subject: %s\n', subj_name);

% ----------------------------------------------------------------
% Path Construction
% ----------------------------------------------------------------
surf_folder_input = fileparts(subject_path);
mri_folder_input = fullfile(fileparts(surf_folder_input), 'mri');
surf_folder_target = fullfile(output_root_path, 'surf');
report_folder_target = fullfile(output_root_path, 'report');
report_folder_input = fullfile(fileparts(surf_folder_input), 'report');

% Create output directories
mkdir(surf_folder_target);
mkdir(report_folder_target);

% CAT12 atlas directories
atlas_vol_dir = fullfile(spm('dir'), 'toolbox', 'cat12', 'templates_volumes');
atlas_surf_dir = fullfile(spm('dir'), 'toolbox', 'cat12', 'atlases_surfaces');

fprintf('\n========================================\n');
fprintf('ATLAS DIRECTORIES\n');
fprintf('========================================\n');
fprintf('Volume atlases: %s\n', atlas_vol_dir);
fprintf('Surface atlases: %s\n', atlas_surf_dir);

% Initialize master data structure
master_data = struct();
master_data.SubjectID = {subj_name};

% ========================================================================
% PART 1: VOLUMETRIC ROI EXTRACTION (GM, WM, CSF)
% ========================================================================

fprintf('\n========================================\n');
fprintf('PART 1: VOLUMETRIC ROI EXTRACTION\n');
fprintf('========================================\n');

% Define volume atlases
volume_atlases = {
    'Hammers_mith_atlas_n30r83_SPM5.nii', 'Hammers';
    'lpba40.nii', 'LPBA40';
    'neuromorphometrics.nii', 'Neuromorphometrics';
    'cobra.nii', 'COBRA';
    'aparc_DK40.nii', 'Desikan_Killiany';
    'aparc_a2009s.nii', 'Destrieux'
};

% Locate tissue segmentation files
gm_file = fullfile(mri_folder_input, ['mwp1' subj_name '.nii']);  % Modulated GM
wm_file = fullfile(mri_folder_input, ['mwp2' subj_name '.nii']);  % Modulated WM
csf_file = fullfile(mri_folder_input, ['mwp3' subj_name '.nii']); % Modulated CSF

fprintf('\nSearching for tissue segmentation files:\n');
fprintf('  GM:  %s [%s]\n', gm_file, char(exist(gm_file, 'file')*'OK' + ~exist(gm_file, 'file')*'MISSING'));
fprintf('  WM:  %s [%s]\n', wm_file, char(exist(wm_file, 'file')*'OK' + ~exist(wm_file, 'file')*'MISSING'));
fprintf('  CSF: %s [%s]\n', csf_file, char(exist(csf_file, 'file')*'OK' + ~exist(csf_file, 'file')*'MISSING'));

if ~exist(gm_file, 'file') || ~exist(wm_file, 'file') || ~exist(csf_file, 'file')
    warning('One or more tissue files not found. Skipping volumetric analysis.');
else
    fprintf('\n--- Loading tissue volumes ---\n');
    V_gm = spm_vol(gm_file);
    V_wm = spm_vol(wm_file);
    V_csf = spm_vol(csf_file);
    
    gm_data = spm_read_vols(V_gm);
    wm_data = spm_read_vols(V_wm);
    csf_data = spm_read_vols(V_csf);
    
    voxel_volume = abs(det(V_gm.mat(1:3, 1:3))); % mm³ per voxel
    fprintf('Voxel volume: %.4f mm³\n', voxel_volume);
    
    % Process each volume atlas
    for atlas_idx = 1:size(volume_atlases, 1)
        atlas_file = volume_atlases{atlas_idx, 1};
        atlas_name = volume_atlases{atlas_idx, 2};
        
        fprintf('\n--- Processing Atlas: %s ---\n', atlas_name);
        
        atlas_path = fullfile(atlas_vol_dir, atlas_file);
        
        if ~exist(atlas_path, 'file')
            fprintf('WARNING: Atlas not found: %s\n', atlas_path);
            continue;
        end
        
        % Load atlas
        V_atlas = spm_vol(atlas_path);
        atlas_data = spm_read_vols(V_atlas);
        
        % Get unique ROI labels
        roi_labels = unique(atlas_data(:));
        roi_labels = roi_labels(roi_labels > 0); % Exclude background (0)
        
        fprintf('  Found %d ROIs in atlas\n', length(roi_labels));
        
        % Extract values for each ROI and add to master_data
        for roi_idx = 1:length(roi_labels)
            label = roi_labels(roi_idx);
            roi_mask = (atlas_data == label);
            
            % Create column names
            roi_name = sprintf('%s_ROI%03d', atlas_name, label);
            
            % Calculate volumes (sum of modulated values)
            gm_vol = sum(gm_data(roi_mask), 'omitnan');
            wm_vol = sum(wm_data(roi_mask), 'omitnan');
            csf_vol = sum(csf_data(roi_mask), 'omitnan');
            
            % Add to master data
            master_data.([roi_name '_GM']) = gm_vol;
            master_data.([roi_name '_WM']) = wm_vol;
            master_data.([roi_name '_CSF']) = csf_vol;
        end
        
        fprintf('  Added %d regions with GM/WM/CSF values\n', length(roi_labels));
    end
    
    fprintf('\n--- Volumetric ROI extraction completed ---\n');
end

% ========================================================================
% PART 2: SURFACE ROI EXTRACTION (Thickness + Gyrification)
% ========================================================================

fprintf('\n========================================\n');
fprintf('PART 2: SURFACE ROI EXTRACTION\n');
fprintf('========================================\n');

% Surface files
thickness_lh_input = subject_path;
thickness_rh_input = fullfile(surf_folder_input, ['rh.thickness.' subj_name]);

% Check if required files exist
if ~exist(thickness_lh_input, 'file') || ~exist(thickness_rh_input, 'file')
    error('Thickness files not found');
end

fprintf('Found required surface files\n');

% ====================================================================
% Step 2.1: Resample and Smooth Thickness to 32k
% ====================================================================
smooth_thick_lh_source = fullfile(surf_folder_input, ['s12.lh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_rh_source = fullfile(surf_folder_input, ['s12.rh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_lh_target = fullfile(surf_folder_target, ['s12.lh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_rh_target = fullfile(surf_folder_target, ['s12.rh.thickness.resampled_32k.' subj_name '.gii']);

if ~exist(smooth_thick_lh_source, 'file') || ~exist(smooth_thick_rh_source, 'file')
    fprintf('\n--- Resampling and smoothing thickness to 32k ---\n');
    
    matlabbatch = {};
    
    % LH Thickness
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.data_surf = {thickness_lh_input};
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.nproc = 0;
    matlabbatch{1}.spm.tools.cat.stools.surfresamp.lazy = 0;
    
    % RH Thickness
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.data_surf = {thickness_rh_input};
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.nproc = 0;
    matlabbatch{2}.spm.tools.cat.stools.surfresamp.lazy = 0;
    
    spm_jobman('run', matlabbatch);
    fprintf('Thickness resampling completed\n');
end

% Copy to target
copyfile(smooth_thick_lh_source, smooth_thick_lh_target);
copyfile(smooth_thick_rh_source, smooth_thick_rh_target);

% ====================================================================
% Step 2.2: Process Gyrification
% ====================================================================
gyrification_lh_input = fullfile(surf_folder_input, ['lh.gyrification.' subj_name]);
gyrification_rh_input = fullfile(surf_folder_input, ['rh.gyrification.' subj_name]);

smooth_gyri_lh_source = fullfile(surf_folder_input, ['s12.lh.gyrification.resampled_32k.' subj_name '.gii']);
smooth_gyri_rh_source = fullfile(surf_folder_input, ['s12.rh.gyrification.resampled_32k.' subj_name '.gii']);
smooth_gyri_lh_target = fullfile(surf_folder_target, ['s12.lh.gyrification.resampled_32k.' subj_name '.gii']);
smooth_gyri_rh_target = fullfile(surf_folder_target, ['s12.rh.gyrification.resampled_32k.' subj_name '.gii']);

process_gyrification = false;

if exist(gyrification_lh_input, 'file') && exist(gyrification_rh_input, 'file')
    if ~exist(smooth_gyri_lh_source, 'file') || ~exist(smooth_gyri_rh_source, 'file')
        fprintf('\n--- Resampling and smoothing gyrification to 32k ---\n');
        
        matlabbatch = {};
        
        % LH Gyrification
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.data_surf = {gyrification_lh_input};
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.nproc = 0;
        matlabbatch{1}.spm.tools.cat.stools.surfresamp.lazy = 0;
        
        % RH Gyrification
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.data_surf = {gyrification_rh_input};
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.nproc = 0;
        matlabbatch{2}.spm.tools.cat.stools.surfresamp.lazy = 0;
        
        spm_jobman('run', matlabbatch);
        fprintf('Gyrification resampling completed\n');
    end
    
    copyfile(smooth_gyri_lh_source, smooth_gyri_lh_target);
    copyfile(smooth_gyri_rh_source, smooth_gyri_rh_target);
    
    process_gyrification = true;
else
    fprintf('\nWARNING: Gyrification files not found, skipping gyrification analysis\n');
end

% ====================================================================
% Step 2.3: Extract Surface ROI Values (Both Atlases)
% ====================================================================

surface_atlases = {
    'aparc_DK40', 'DK40';
    'aparc_a2009s', 'Destrieux'
};

for atlas_idx = 1:size(surface_atlases, 1)
    atlas_basename = surface_atlases{atlas_idx, 1};
    atlas_name = surface_atlases{atlas_idx, 2};
    
    fprintf('\n--- Processing Surface Atlas: %s ---\n', atlas_name);
    
    % ---- Process Left Hemisphere ----
    fprintf('  Processing Left Hemisphere:\n');
    
    % Load thickness data
    lh_thick_gii = gifti(smooth_thick_lh_target);
    lh_thickness_data = lh_thick_gii.cdata;
    
    % Load gyrification if available
    if process_gyrification
        lh_gyri_gii = gifti(smooth_gyri_lh_target);
        lh_gyri_data = lh_gyri_gii.cdata;
    end
    
    % Load atlas
    lh_atlas_file = fullfile(atlas_surf_dir, sprintf('lh.%s.freesurfer.annot', atlas_basename));
    if ~exist(lh_atlas_file, 'file')
        fprintf('  WARNING: Atlas not found: %s\n', lh_atlas_file);
        continue;
    end
    
    [~, lh_label, lh_colortable] = cat_io_FreeSurfer('read_annotation', lh_atlas_file);
    
    % Downsample atlas to 32k
    sampling_ratio = round(length(lh_label) / length(lh_thickness_data));
    lh_label_32k = lh_label(1:sampling_ratio:length(lh_label));
    lh_label_32k = lh_label_32k(1:length(lh_thickness_data));
    
    % Extract ROI means
    for i = 1:lh_colortable.numEntries
        region_name = lh_colortable.struct_names{i};
        region_label = lh_colortable.table(i, 5);
        
        roi_mask = (lh_label_32k == region_label);
        n_vertices = sum(roi_mask);
        
        if n_vertices > 0
            % Sanitize region name (remove spaces and special characters)
            region_clean = strrep(region_name, ' ', '_');
            region_clean = strrep(region_clean, '-', '_');
            region_clean = strrep(region_clean, '&', 'and');
            
            % Add thickness to master data
            col_name = sprintf('lh_%s_%s_Thickness', atlas_name, region_clean);
            master_data.(col_name) = mean(lh_thickness_data(roi_mask));
            
            % Add gyrification if available
            if process_gyrification
                col_name_gyri = sprintf('lh_%s_%s_Gyrification', atlas_name, region_clean);
                master_data.(col_name_gyri) = mean(lh_gyri_data(roi_mask));
            end
        end
    end
    
    % ---- Process Right Hemisphere ----
    fprintf('  Processing Right Hemisphere:\n');
    
    % Load thickness data
    rh_thick_gii = gifti(smooth_thick_rh_target);
    rh_thickness_data = rh_thick_gii.cdata;
    
    % Load gyrification if available
    if process_gyrification
        rh_gyri_gii = gifti(smooth_gyri_rh_target);
        rh_gyri_data = rh_gyri_gii.cdata;
    end
    
    % Load atlas
    rh_atlas_file = fullfile(atlas_surf_dir, sprintf('rh.%s.freesurfer.annot', atlas_basename));
    if ~exist(rh_atlas_file, 'file')
        fprintf('  WARNING: Atlas not found: %s\n', rh_atlas_file);
        continue;
    end
    
    [~, rh_label, rh_colortable] = cat_io_FreeSurfer('read_annotation', rh_atlas_file);
    
    % Downsample atlas to 32k
    sampling_ratio = round(length(rh_label) / length(rh_thickness_data));
    rh_label_32k = rh_label(1:sampling_ratio:length(rh_label));
    rh_label_32k = rh_label_32k(1:length(rh_thickness_data));
    
    % Extract ROI means
    for i = 1:rh_colortable.numEntries
        region_name = rh_colortable.struct_names{i};
        region_label = rh_colortable.table(i, 5);
        
        roi_mask = (rh_label_32k == region_label);
        n_vertices = sum(roi_mask);
        
        if n_vertices > 0
            % Sanitize region name
            region_clean = strrep(region_name, ' ', '_');
            region_clean = strrep(region_clean, '-', '_');
            region_clean = strrep(region_clean, '&', 'and');
            
            % Add thickness to master data
            col_name = sprintf('rh_%s_%s_Thickness', atlas_name, region_clean);
            master_data.(col_name) = mean(rh_thickness_data(roi_mask));
            
            % Add gyrification if available
            if process_gyrification
                col_name_gyri = sprintf('rh_%s_%s_Gyrification', atlas_name, region_clean);
                master_data.(col_name_gyri) = mean(rh_gyri_data(roi_mask));
            end
        end
    end
    
    fprintf('  Completed atlas %s\n', atlas_name);
end

% ====================================================================
% Save Combined CSV File
% ====================================================================
fprintf('\n--- Creating combined CSV output ---\n');

% Convert struct to table
T_combined = struct2table(master_data);

% Save to CSV
csv_output = fullfile(report_folder_target, [subj_name '_ROI_all.csv']);
writetable(T_combined, csv_output);

fprintf('SUCCESS: Combined CSV saved to %s\n', csv_output);
fprintf('  Total columns: %d\n', width(T_combined));
fprintf('  Subject ID: %s\n', subj_name);

% ====================================================================
% Copy CAT Report Files
% ====================================================================
fprintf('\n--- Copying CAT Report Files ---\n');
cat_xml_input = fullfile(report_folder_input, ['cat_' subj_name '.xml']);
cat_mat_input = fullfile(report_folder_input, ['cat_' subj_name '.mat']);

if exist(cat_xml_input, 'file')
    copyfile(cat_xml_input, fullfile(report_folder_target, ['cat_' subj_name '.xml']));
    fprintf('Copied CAT XML file\n');
end

if exist(cat_mat_input, 'file')
    copyfile(cat_mat_input, fullfile(report_folder_target, ['cat_' subj_name '.mat']));
    fprintf('Copied CAT MAT file\n');
end

% ========================================================================
% FINAL SUMMARY
% ========================================================================
fprintf('\n========================================\n');
fprintf('COMPLETE ROI EXTRACTION FINISHED\n');
fprintf('========================================\n');
fprintf('Subject: %s\n', subj_name);
fprintf('Output file: %s\n', csv_output);
fprintf('Total metrics: %d columns\n\n', width(T_combined));

fprintf('INCLUDED DATA:\n');
fprintf('  VOLUMETRIC (GM, WM, CSF):\n');
fprintf('    - Hammers\n');
fprintf('    - LPBA40\n');
fprintf('    - Neuromorphometrics\n');
fprintf('    - COBRA\n');
fprintf('    - Desikan-Killiany\n');
fprintf('    - Destrieux\n\n');

fprintf('  SURFACE:\n');
fprintf('    - Thickness: DK40, Destrieux\n');
if process_gyrification
    fprintf('    - Gyrification: DK40, Destrieux\n');
end

fprintf('\nColumn naming convention:\n');
fprintf('  Volume: <Atlas>_ROI<###>_<Tissue>\n');
fprintf('    Example: Hammers_ROI001_GM\n');
fprintf('  Surface: <hemi>_<Atlas>_<Region>_<Metric>\n');
fprintf('    Example: lh_DK40_Precentral_Thickness\n');

fprintf('\nProcessing specifications:\n');
fprintf('  - Smoothing: 12mm FWHM\n');
fprintf('  - Surface mesh: 32k vertices\n');
fprintf('  - Tissue volumes: Modulated (absolute mm³)\n');
fprintf('========================================\n');

exit(0);