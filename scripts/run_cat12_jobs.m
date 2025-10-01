% CAT12 Post-Segmentation Processing Script
% Extracts gyrification, smooths surfaces, and extracts ROI values
% Skript wurde angepasst, um alle Outputs in den per OUTPUT_ROOT definierten ZIEL-Pfad zu schreiben.

% Set the paths to your SPM and CAT12 installations (diese Pfade werden nur gelesen)
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12');
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12');

spm('defaults', 'FMRI');
spm_jobman('initcfg');

% ----------------------------------------------------------------
% Pfad-Definition basierend auf Umgebungsvariablen
% ----------------------------------------------------------------
% INPUT: Pfad zur lh.thickness-Datei im stumrani-Ordner
subject_path = getenv('SUBJECT_PATH'); 
% OUTPUT: Pfad zum Subjekt-Ordner im lduttenhoefer-Ordner
output_root_path = getenv('OUTPUT_ROOT'); 

if isempty(subject_path)
    error('SUBJECT_PATH environment variable is not defined.');
end
if isempty(output_root_path)
    error('OUTPUT_ROOT environment variable is not defined. Cannot determine output path.');
end

% --- ROBUSTE SUBJEKTNAME-EXTRAKTION ---
if ispc
    parts = strsplit(subject_path, '\');
else
    parts = strsplit(subject_path, '/');
end
filename_full = parts{end};

fprintf('DEBUG: Full filename extracted = %s\n', filename_full);

% Entferne 'lh.thickness.' vom Anfang mit strrep
subj_name = strrep(filename_full, 'lh.thickness.', '');

fprintf('DEBUG: Subject name after prefix removal = %s\n', subj_name);

% Validierung
if isempty(subj_name) || strcmp(subj_name, 'lh') || strcmp(subj_name, 'rh') || strcmp(subj_name, 'lh.thickness')
    error('FEHLER: Ungültiger Subject Name extrahiert: %s (Original: %s)', subj_name, subject_path);
end

fprintf('DEBUG: subject_path (INPUT) = %s\n', subject_path);
fprintf('DEBUG: output_root_path (TARGET) = %s\n', output_root_path);
fprintf('DEBUG: subj_name = %s\n', subj_name);
fprintf('Processing post-segmentation for subject: %s\n', subj_name);

% ----------------------------------------------------------------
% Pfad-Konstruktion
% ----------------------------------------------------------------
surf_folder_input = fileparts(subject_path);
surf_folder_target = fullfile(output_root_path, 'surf');
report_folder_target = fullfile(output_root_path, 'report');

% Central surface files (Input für Job 1)
central_surface_lh = fullfile(surf_folder_input, ['lh.central.' subj_name '.gii']);
central_surface_rh = fullfile(surf_folder_input, ['rh.central.' subj_name '.gii']);

% Thickness files (Input für Job 2)
thickness_lh_input = subject_path;
thickness_rh_input = fullfile(surf_folder_input, ['rh.thickness.' subj_name]);

% Gyrification files (werden von Job 1 erstellt und dann verschoben - KEINE Glättung)
gyri_lh_source = fullfile(surf_folder_input, ['lh.gyrification.' subj_name]);
gyri_rh_source = fullfile(surf_folder_input, ['rh.gyrification.' subj_name]);
gyri_lh_target = fullfile(surf_folder_target, ['lh.gyrification.' subj_name]);
gyri_rh_target = fullfile(surf_folder_target, ['rh.gyrification.' subj_name]);

% Smoothed files (werden im INPUT-Ordner erstellt, müssen verschoben werden)
smooth_thick_lh_source = fullfile(surf_folder_input, ['s12.lh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_rh_source = fullfile(surf_folder_input, ['s12.rh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_lh_target = fullfile(surf_folder_target, ['s12.lh.thickness.resampled_32k.' subj_name '.gii']);
smooth_thick_rh_target = fullfile(surf_folder_target, ['s12.rh.thickness.resampled_32k.' subj_name '.gii']);

% Check if required files exist
if ~exist(thickness_lh_input, 'file')
    error('LH Thickness file not found: %s', thickness_lh_input);
end
if ~exist(central_surface_lh, 'file')
    error('LH Central surface file not found: %s', central_surface_lh);
end

fprintf('Found required INPUT files\n');

% ----------------------------------------------------------------
% BATCH DEFINITION
% ----------------------------------------------------------------
matlabbatch = {};

% ========================================================================
% Job 1: Extract Gyrification
% ========================================================================
matlabbatch{1}.spm.tools.cat.stools.surfextract.data_surf = {central_surface_lh};
matlabbatch{1}.spm.tools.cat.stools.surfextract.GI = 1; 
matlabbatch{1}.spm.tools.cat.stools.surfextract.FD = 0; 
matlabbatch{1}.spm.tools.cat.stools.surfextract.SD = 0; 
matlabbatch{1}.spm.tools.cat.stools.surfextract.nproc = 0;
matlabbatch{1}.spm.tools.cat.stools.surfextract.lazy = 0;

fprintf('Job 1: Extract gyrification configured\n');

% ========================================================================
% Jobs 2-3: Resample and Smooth - NUR THICKNESS
% (Gyrification wird NICHT geglättet - wissenschaftlich vertretbar)
% ========================================================================
% Job 2: LH Thickness
matlabbatch{2}.spm.tools.cat.stools.surfresamp.data_surf = {thickness_lh_input};
matlabbatch{2}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
matlabbatch{2}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
matlabbatch{2}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
matlabbatch{2}.spm.tools.cat.stools.surfresamp.nproc = 0;
matlabbatch{2}.spm.tools.cat.stools.surfresamp.lazy = 0;

% Job 3: RH Thickness
matlabbatch{3}.spm.tools.cat.stools.surfresamp.data_surf = {thickness_rh_input};
matlabbatch{3}.spm.tools.cat.stools.surfresamp.merge_hemi = 0;
matlabbatch{3}.spm.tools.cat.stools.surfresamp.mesh32k = 1;
matlabbatch{3}.spm.tools.cat.stools.surfresamp.fwhm_surf = 12;
matlabbatch{3}.spm.tools.cat.stools.surfresamp.nproc = 0;
matlabbatch{3}.spm.tools.cat.stools.surfresamp.lazy = 0;

fprintf('Jobs 2-3: Thickness resampling configured\n');
fprintf('NOTE: Gyrification will NOT be smoothed (kept at native resolution)\n');

% ========================================================================
% Job 4: Extract ROI Values
% Struktur: Getrennte Einträge pro Datentyp und Hemisphäre
% ========================================================================
% Erstelle separate Jobs für LH und RH
matlabbatch{4}.spm.tools.cat.stools.surf2roi.cdata = {
     smooth_thick_lh_target
};
 
matlabbatch{4}.spm.tools.cat.stools.surf2roi.rdata = {
     fullfile(spm('dir'), 'toolbox', 'cat12', 'atlases_surfaces', 'lh.aparc_DK40.freesurfer.annot')
};

matlabbatch{5}.spm.tools.cat.stools.surf2roi.cdata = {
     smooth_thick_rh_target
};
 
matlabbatch{5}.spm.tools.cat.stools.surf2roi.rdata = {
     fullfile(spm('dir'), 'toolbox', 'cat12', 'atlases_surfaces', 'rh.aparc_DK40.freesurfer.annot')
};

matlabbatch{6}.spm.tools.cat.stools.surf2roi.cdata = {
     gyri_lh_target
};
 
matlabbatch{6}.spm.tools.cat.stools.surf2roi.rdata = {
     fullfile(spm('dir'), 'toolbox', 'cat12', 'atlases_surfaces', 'lh.aparc_DK40.freesurfer.annot')
};

matlabbatch{7}.spm.tools.cat.stools.surf2roi.cdata = {
     gyri_rh_target
};
 
matlabbatch{7}.spm.tools.cat.stools.surf2roi.rdata = {
     fullfile(spm('dir'), 'toolbox', 'cat12', 'atlases_surfaces', 'rh.aparc_DK40.freesurfer.annot')
};

fprintf('Jobs 4-7: ROI extraction configured (separate jobs per metric and hemisphere)\n');

% ========================================================================
% Run the batch
% ========================================================================
fprintf('\n========================================\n');
fprintf('Starting CAT12 batch processing...\n');
fprintf('========================================\n');

try
    % Job 1: Extract Gyrification
    fprintf('\n--- Running Job 1: Extract Gyrification ---\n');
    spm_jobman('run', matlabbatch(1)); 
    
    fprintf('\nJob 1 completed. Moving gyrification files...\n');
    
    % Verschiebe BEIDE Hemisphären (OHNE Konvertierung oder Glättung)
    if exist(gyri_lh_source, 'file')
        movefile(gyri_lh_source, gyri_lh_target);
        fprintf('Moved LH gyrification file (native resolution, no smoothing)\n');
    else
        error('LH gyrification file not created: %s', gyri_lh_source);
    end
    
    if exist(gyri_rh_source, 'file')
        movefile(gyri_rh_source, gyri_rh_target);
        fprintf('Moved RH gyrification file (native resolution, no smoothing)\n');
    else
        error('RH gyrification file not created: %s', gyri_rh_source);
    end
    
    fprintf('NOTE: Gyrification values kept at native resolution (unsmoothed)\n');
    fprintf('This is scientifically valid as gyrification is an intrinsic geometric property.\n');
    
    % Jobs 2-3: Resample and Smooth (nur Thickness)
    fprintf('\n--- Running Jobs 2-3: Resample and Smooth Thickness ---\n');
    spm_jobman('run', matlabbatch(2:3));
    
    % Verschiebe die gesmoothten Thickness-Dateien zum Ziel-Ordner
    fprintf('\nMoving smoothed thickness files to target directory...\n');
    if exist(smooth_thick_lh_source, 'file')
        movefile(smooth_thick_lh_source, smooth_thick_lh_target);
        fprintf('Moved smoothed LH thickness file\n');
    else
        error('Smoothed LH thickness file not created: %s', smooth_thick_lh_source);
    end
    
    if exist(smooth_thick_rh_source, 'file')
        movefile(smooth_thick_rh_source, smooth_thick_rh_target);
        fprintf('Moved smoothed RH thickness file\n');
    else
        error('Smoothed RH thickness file not created: %s', smooth_thick_rh_source);
    end
    
    % Job 4-7: ROI Extraction (separate for each hemisphere and metric)
    fprintf('\n--- Running Jobs 4-7: ROI Extraction ---\n');
    spm_jobman('run', matlabbatch(4:7));

    fprintf('\n========================================\n');
    fprintf('CAT12 surface analysis and ROI extraction completed successfully for %s.\n', subj_name);
    fprintf('All outputs stored in: %s\n', output_root_path);
    fprintf('========================================\n');
    
catch ME
    fprintf('\n========================================\n');
    fprintf('ERROR during CAT12 processing for %s\n', subj_name);
    fprintf('Error message: %s\n', ME.message);
    fprintf('Error stack:\n');
    disp(getReport(ME));
    fprintf('========================================\n');
    exit(1);
end

exit(0);