% Add SPM12 and CAT12 paths
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12');
addpath('/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12');

% Initialize SPM
spm('defaults', 'FMRI');
spm_jobman('initcfg');

% Get environment variables
subject_path = getenv('SUBJECT_PATH');
output_root = getenv('OUTPUT_ROOT');

if isempty(subject_path) || isempty(output_root)
    error('SUBJECT_PATH or OUTPUT_ROOT not defined.');
end

fprintf('Processing subject: %s\n', subject_path);
fprintf('Output directory: %s\n', output_root);

% Copy input file directly to output_root (not a subdirectory)
[~, subject_filename, ext] = fileparts(subject_path);
local_input = fullfile(output_root, [subject_filename, ext]);
copyfile(subject_path, local_input);

% Handle .nii.gz files: remove .nii extension from subject_filename for file matching
% CAT12 creates output files without the .nii extension when input is .nii.gz
if strcmp(ext, '.gz') && endsWith(subject_filename, '.nii')
    subject_filename = subject_filename(1:end-4);  % Remove '.nii'
    fprintf('Adjusted subject_filename for .nii.gz: %s\n', subject_filename);
end

% =========================================================================
% BATCH 1: CAT12 SEGMENTATION
% =========================================================================
matlabbatch = {};
matlabbatch{1}.spm.tools.cat.estwrite.data{1} = local_input;

% CAT12 options
matlabbatch{1}.spm.tools.cat.estwrite.nproc = 1;
matlabbatch{1}.spm.tools.cat.estwrite.opts.tpm = {'/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/tpm/TPM.nii'};
matlabbatch{1}.spm.tools.cat.estwrite.opts.affreg = 'mni';

% Extended options
matlabbatch{1}.spm.tools.cat.estwrite.extopts.APP = 1070;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.LASstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.gcutstr = 2;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shooting.shootingtpm = {'/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12/templates_MNI152NLin2009cAsym/Template_0_GS.nii'};
matlabbatch{1}.spm.tools.cat.estwrite.extopts.registration.shooting.regstr = 0.5;
matlabbatch{1}.spm.tools.cat.estwrite.extopts.vox = 1.5;

% Surface outputs
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 1;

% Volume outputs
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.GM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.mod = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.WM.dartel = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.mod = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.CSF.dartel = 0;

% Labels
matlabbatch{1}.spm.tools.cat.estwrite.output.label.native = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.warped = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.label.dartel = 0;

% Bias correction
matlabbatch{1}.spm.tools.cat.estwrite.output.bias.warped = 1;

% Jacobian determinant
matlabbatch{1}.spm.tools.cat.estwrite.output.jacobianwarped = 0;

% Deformation fields
matlabbatch{1}.spm.tools.cat.estwrite.output.warps = [1 0];

% Volume-basierte Atlanten aktivieren
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.lpba40 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.cobra = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.suit = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.hammers = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ibsr = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.thalamus = 0;
% AAL3 als eigener Atlas
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ownatlas = {'/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12/templates_MNI152NLin2009cAsym/aal3.nii'};

% =========================================================================
% BATCH 2: EXTRACT SURFACE MEASURES (GYRIFICATION, etc.)
% =========================================================================
% Use dependency to get left central surface from batch 1
matlabbatch{2}.spm.tools.cat.stools.surfextract.data_surf(1) = cfg_dep('CAT12: Segmentation: Left Central Surface', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('()',{1}, '.','lhcentral', '()',{':'}));
matlabbatch{2}.spm.tools.cat.stools.surfextract.GI = 1;  % Gyrification Index
matlabbatch{2}.spm.tools.cat.stools.surfextract.SD = 1;  % Sulcus Depth
matlabbatch{2}.spm.tools.cat.stools.surfextract.FD = 0;  % Fractal Dimension
matlabbatch{2}.spm.tools.cat.stools.surfextract.nproc = 0;

% Run CAT12 segmentation + surface extraction
try
    spm_jobman('run', matlabbatch);
    fprintf('CAT12 processing completed successfully\n');
catch ME
    fprintf('Error during CAT12 processing: %s\n', ME.message);
    disp(getReport(ME));
    exit(1);
end

% =========================================================================
% SURFACE ROI EXTRACTION
% =========================================================================
fprintf('\n=== Running surface ROI extraction ===\n');

% Check both possible directory structures
% Option 1: Flat structure (all files directly in output_root)
% Option 2: Subfolder structure (files in surf/, label/, report/)

% Try flat structure first
surf_dir = output_root;
label_dir = output_root;
report_dir = output_root;

lh_thick = fullfile(surf_dir, ['lh.thickness.', subject_filename]);

% If not found in flat structure, try subfolder structure
if ~exist(lh_thick, 'file')
    fprintf('Files not in flat structure, checking subfolders...\n');
    surf_dir = fullfile(output_root, 'surf');
    label_dir = fullfile(output_root, 'label');
    report_dir = fullfile(output_root, 'report');
    lh_thick = fullfile(surf_dir, ['lh.thickness.', subject_filename]);
end

fprintf('Using directories:\n');
fprintf('  surf_dir: %s\n', surf_dir);
fprintf('  label_dir: %s\n', label_dir);
fprintf('  report_dir: %s\n', report_dir);

% Check if thickness files exist
rh_thick = fullfile(surf_dir, ['rh.thickness.', subject_filename]);

if exist(lh_thick, 'file') && exist(rh_thick, 'file')
    % Define which surface atlases to use
    atlas_dir = '/net/data.isilon/ag-cherrmann/stumrani/caton/spm12/toolbox/cat12/atlases_surfaces';
    
    surf_job = struct();
    surf_job.verb = 1;
    
    % Thickness data
    surf_job.cdata{1} = {lh_thick};
    surf_job.cdata{2} = {rh_thick};
    
    % Define atlases (DK40 and Destrieux)
    surf_job.rdata = {
        fullfile(atlas_dir, 'lh.aparc_DK40.freesurfer.annot');
        fullfile(atlas_dir, 'lh.aparc_a2009s.freesurfer.annot');
    };
    
    try
        cat_surf_surf2roi(surf_job);
        fprintf('Surface ROI extraction for thickness completed\n');
    catch ME
        fprintf('Warning: Surface ROI extraction for thickness failed: %s\n', ME.message);
        disp(getReport(ME));
    end
    
    % Now do gyrification
    lh_gyri = fullfile(surf_dir, ['lh.gyrification.', subject_filename]);
    rh_gyri = fullfile(surf_dir, ['rh.gyrification.', subject_filename]);
    
    if exist(lh_gyri, 'file') && exist(rh_gyri, 'file')
        surf_job_gyri = struct();
        surf_job_gyri.verb = 1;
        
        % Gyrification data
        surf_job_gyri.cdata{1} = {lh_gyri};
        surf_job_gyri.cdata{2} = {rh_gyri};
        
        % Same atlases
        surf_job_gyri.rdata = {
            fullfile(atlas_dir, 'lh.aparc_DK40.freesurfer.annot');
            fullfile(atlas_dir, 'lh.aparc_a2009s.freesurfer.annot');
        };
        
        try
            cat_surf_surf2roi(surf_job_gyri);
            fprintf('Surface ROI extraction for gyrification completed\n');
        catch ME
            fprintf('Warning: Surface ROI extraction for gyrification failed: %s\n', ME.message);
            disp(getReport(ME));
        end
    else
        fprintf('Warning: Gyrification files not found\n');
        fprintf('Expected: %s\n', lh_gyri);
    end
else
    fprintf('Warning: Thickness files not found at expected location\n');
    fprintf('Expected: %s\n', lh_thick);
end

% =========================================================================
% POST-PROCESSING: Extract all metrics
% =========================================================================
fprintf('\n=== Starting data extraction ===\n');

result = struct();
result.Subject = subject_filename;

% 1. QUALITY MEASURES
xml_file = fullfile(report_dir, ['cat_', subject_filename, '.xml']);
if exist(xml_file, 'file')
    try
        qa_data = cat_io_xml(xml_file);
        result.IQR = qa_data.qualityratings.IQR;
        result.NCR = qa_data.qualityratings.NCR;
        result.ICR = qa_data.qualityratings.ICR;
        result.res_RMS = qa_data.qualityratings.res_RMS;
        result.TIV = qa_data.subjectmeasures.vol_TIV;
        result.GM_vol = qa_data.subjectmeasures.vol_rel_CGW(1) * result.TIV;
        result.WM_vol = qa_data.subjectmeasures.vol_rel_CGW(2) * result.TIV;
        result.CSF_vol = qa_data.subjectmeasures.vol_rel_CGW(3) * result.TIV;
        if length(qa_data.subjectmeasures.vol_rel_CGW) >= 4
            result.WMH_vol = qa_data.subjectmeasures.vol_rel_CGW(4) * result.TIV;
        else
            result.WMH_vol = NaN;
        end
        fprintf('Quality measures extracted\n');
    catch ME
        fprintf('Warning: Could not read XML: %s\n', ME.message);
        result.IQR = NaN; result.NCR = NaN; result.ICR = NaN; 
        result.res_RMS = NaN; result.TIV = NaN; result.GM_vol = NaN; 
        result.WM_vol = NaN; result.CSF_vol = NaN; result.WMH_vol = NaN;
    end
else
    fprintf('Warning: QC XML file not found: %s\n', xml_file);
    result.IQR = NaN; result.NCR = NaN; result.ICR = NaN; 
    result.res_RMS = NaN; result.TIV = NaN; result.GM_vol = NaN; 
    result.WM_vol = NaN; result.CSF_vol = NaN; result.WMH_vol = NaN;
end

% 2. CORTICAL THICKNESS (global)
if exist(lh_thick, 'file') && exist(rh_thick, 'file')
    try
        lh_data = cat_io_FreeSurfer('read_surf_data', lh_thick);
        rh_data = cat_io_FreeSurfer('read_surf_data', rh_thick);
        result.mean_thickness_lh = mean(lh_data, 'omitnan');
        result.mean_thickness_rh = mean(rh_data, 'omitnan');
        result.mean_thickness_global = mean([lh_data; rh_data], 'omitnan');
        fprintf('Global thickness extracted\n');
    catch ME
        result.mean_thickness_lh = NaN;
        result.mean_thickness_rh = NaN;
        result.mean_thickness_global = NaN;
    end
else
    result.mean_thickness_lh = NaN;
    result.mean_thickness_rh = NaN;
    result.mean_thickness_global = NaN;
end

% 3. GYRIFICATION (global)
lh_gyri = fullfile(surf_dir, ['lh.gyrification.', subject_filename]);
rh_gyri = fullfile(surf_dir, ['rh.gyrification.', subject_filename]);
if exist(lh_gyri, 'file') && exist(rh_gyri, 'file')
    try
        lh_data = cat_io_FreeSurfer('read_surf_data', lh_gyri);
        rh_data = cat_io_FreeSurfer('read_surf_data', rh_gyri);
        result.mean_gyri_lh = mean(lh_data, 'omitnan');
        result.mean_gyri_rh = mean(rh_data, 'omitnan');
        result.mean_gyri_global = mean([lh_data; rh_data], 'omitnan');
        fprintf('Global gyrification extracted\n');
    catch ME
        result.mean_gyri_lh = NaN;
        result.mean_gyri_rh = NaN;
        result.mean_gyri_global = NaN;
    end
else
    result.mean_gyri_lh = NaN;
    result.mean_gyri_rh = NaN;
    result.mean_gyri_global = NaN;
end

% 4. ROI EXTRACTION - Volume atlases mit Vgm, Vwm, Vcsf
roi_file = fullfile(label_dir, ['catROI_', subject_filename, '.xml']);

% Liste der gewünschten Atlanten (AAL3 wird als 'aal3' in der XML erscheinen)
desired_atlases = {'neuromorphometrics', 'lpba40', 'cobra', 'suit', 'ibsr', 'aal3'};

if exist(roi_file, 'file')
    try
        roi_data = cat_io_xml(roi_file);
        
        % Debug: Zeige alle verfügbaren Atlanten im XML
        available_atlases = fieldnames(roi_data);
        fprintf('Available atlases in XML: %s\n', strjoin(available_atlases, ', '));
        
        for atlas_idx = 1:length(desired_atlases)
            atlas_name = desired_atlases{atlas_idx};
            
            % Versuche verschiedene Namensformate für den Atlas
            possible_names = {atlas_name, strrep(atlas_name, '_', ''), lower(atlas_name), upper(atlas_name)};
            atlas_found = false;
            actual_atlas_name = '';
            
            for name_idx = 1:length(possible_names)
                if isfield(roi_data, possible_names{name_idx})
                    actual_atlas_name = possible_names{name_idx};
                    atlas_found = true;
                    break;
                end
            end
            
            if ~atlas_found
                fprintf('Warning: Atlas %s not found in XML (tried: %s)\n', atlas_name, strjoin(possible_names, ', '));
                continue;
            end
            
            atlas_struct = roi_data.(actual_atlas_name);
            
            % Extract names - can be in different formats
            if isfield(atlas_struct, 'names')
                if isstruct(atlas_struct.names)
                    if isfield(atlas_struct.names, 'item')
                        if iscell(atlas_struct.names.item)
                            roi_names = atlas_struct.names.item;
                        else
                            roi_names = {atlas_struct.names.item};
                        end
                    else
                        continue;
                    end
                elseif iscell(atlas_struct.names)
                    roi_names = atlas_struct.names;
                else
                    continue;
                end
            else
                continue;
            end
            
            % Extract volumes - Vgm, Vwm, Vcsf
            roi_vgm = [];
            roi_vwm = [];
            roi_vcsf = [];
            
            if isfield(atlas_struct, 'data')
                if isfield(atlas_struct.data, 'Vgm')
                    roi_vgm = atlas_struct.data.Vgm;
                end
                if isfield(atlas_struct.data, 'Vwm')
                    roi_vwm = atlas_struct.data.Vwm;
                end
                if isfield(atlas_struct.data, 'Vcsf')
                    roi_vcsf = atlas_struct.data.Vcsf;
                end
            elseif isfield(atlas_struct, 'Vgm')
                roi_vgm = atlas_struct.Vgm;
                if isfield(atlas_struct, 'Vwm')
                    roi_vwm = atlas_struct.Vwm;
                end
                if isfield(atlas_struct, 'Vcsf')
                    roi_vcsf = atlas_struct.Vcsf;
                end
            end
            
            % Kürze Atlas-Namen für CSV
            atlas_name_short = atlas_name;
            if strcmp(atlas_name, 'neuromorphometrics')
                atlas_name_short = 'Neurom';
            elseif strcmp(lower(atlas_name), 'aal3')
                atlas_name_short = 'AAL3';
            elseif strcmp(atlas_name, 'ibsr')
                atlas_name_short = 'IBSR';
            elseif strcmp(atlas_name, 'suit')
                atlas_name_short = 'SUIT';
            end
            
            % Add to result structure
            for r = 1:length(roi_names)
                roi_name = roi_names{r};
                roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_name]);
                
                % Vgm (graue Substanz)
                if r <= length(roi_vgm)
                    result.(['Vgm_', roi_name_clean]) = roi_vgm(r);
                end
                
                % Vwm (weiße Substanz)
                if r <= length(roi_vwm)
                    result.(['Vwm_', roi_name_clean]) = roi_vwm(r);
                end
                
                % Vcsf (Liquor)
                if r <= length(roi_vcsf)
                    result.(['Vcsf_', roi_name_clean]) = roi_vcsf(r);
                end
            end
            
            fprintf('Extracted %s atlas (%d regions, Vgm=%d, Vwm=%d, Vcsf=%d)\n', ...
                atlas_name, length(roi_names), ~isempty(roi_vgm), ~isempty(roi_vwm), ~isempty(roi_vcsf));
        end
        
    catch ME
        fprintf('Warning: Error reading ROI file: %s\n', ME.message);
        disp(getReport(ME));
    end
else
    fprintf('Warning: ROI file not found: %s\n', roi_file);
end

% 5. EXTRACT SURFACE ROI DATA (aparc_DK40, aparc_a2009s)
surface_roi_xml = fullfile(label_dir, ['catROIs_', subject_filename, '.xml']);

if exist(surface_roi_xml, 'file')
    try
        surface_roi_data = cat_io_xml(surface_roi_xml);
        surface_atlases = fieldnames(surface_roi_data);
        
        for atlas_idx = 1:length(surface_atlases)
            atlas_name = surface_atlases{atlas_idx};
            
            % Skip non-atlas fields
            if strcmp(atlas_name, 'help') || strcmp(atlas_name, 'version') || strcmp(atlas_name, 'comments')
                continue;
            end
            
            atlas_struct = surface_roi_data.(atlas_name);
            
            % Extract names
            if isfield(atlas_struct, 'names')
                if iscell(atlas_struct.names)
                    roi_names = atlas_struct.names;
                elseif isstruct(atlas_struct.names) && isfield(atlas_struct.names, 'item')
                    roi_names = atlas_struct.names.item;
                    if ~iscell(roi_names)
                        roi_names = {roi_names};
                    end
                else
                    continue;
                end
            else
                continue;
            end
            
            % Kurznamen für die Surface-Atlanten
            atlas_name_short = atlas_name;
            if contains(atlas_name, 'DK40') || contains(atlas_name, 'aparc_DK40')
                atlas_name_short = 'DK40';
            elseif contains(atlas_name, 'a2009s') || contains(atlas_name, 'Destrieux')
                atlas_name_short = 'Destrieux';
            end
            
            % Extract thickness if available
            if isfield(atlas_struct, 'data') && isfield(atlas_struct.data, 'thickness')
                roi_thickness = atlas_struct.data.thickness;
                
                for r = 1:length(roi_names)
                    roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_names{r}]);
                    if r <= length(roi_thickness)
                        result.(['T_', roi_name_clean]) = roi_thickness(r);
                    end
                end
                
                fprintf('Extracted %s thickness (%d regions)\n', atlas_name, length(roi_names));
            end
            
            % Extract gyrification if available
            if isfield(atlas_struct, 'data') && isfield(atlas_struct.data, 'gyrification')
                roi_gyri = atlas_struct.data.gyrification;
                
                for r = 1:length(roi_names)
                    roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_names{r}]);
                    if r <= length(roi_gyri)
                        result.(['G_', roi_name_clean]) = roi_gyri(r);
                    end
                end
                
                fprintf('Extracted %s gyrification (%d regions)\n', atlas_name, length(roi_names));
            end
            
            % Extract VOLUMES if available (Vgm, Vwm, Vcsf)
            % CAT12 kann diese für Surface-Atlanten bereitstellen
            if isfield(atlas_struct, 'data')
                % GM Volume
                if isfield(atlas_struct.data, 'Vgm')
                    roi_vgm = atlas_struct.data.Vgm;
                    for r = 1:length(roi_names)
                        roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_names{r}]);
                        if r <= length(roi_vgm)
                            result.(['Vgm_', roi_name_clean]) = roi_vgm(r);
                        end
                    end
                    fprintf('Extracted %s Vgm volumes (%d regions)\n', atlas_name, length(roi_vgm));
                end
                
                % WM Volume
                if isfield(atlas_struct.data, 'Vwm')
                    roi_vwm = atlas_struct.data.Vwm;
                    for r = 1:length(roi_names)
                        roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_names{r}]);
                        if r <= length(roi_vwm)
                            result.(['Vwm_', roi_name_clean]) = roi_vwm(r);
                        end
                    end
                    fprintf('Extracted %s Vwm volumes (%d regions)\n', atlas_name, length(roi_vwm));
                end
                
                % CSF Volume
                if isfield(atlas_struct.data, 'Vcsf')
                    roi_vcsf = atlas_struct.data.Vcsf;
                    for r = 1:length(roi_names)
                        roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_names{r}]);
                        if r <= length(roi_vcsf)
                            result.(['Vcsf_', roi_name_clean]) = roi_vcsf(r);
                        end
                    end
                    fprintf('Extracted %s Vcsf volumes (%d regions)\n', atlas_name, length(roi_vcsf));
                end
            end
        end
    catch ME
        fprintf('Warning: Error reading surface ROI file: %s\n', ME.message);
        disp(getReport(ME));
    end
else
    fprintf('Warning: Surface ROI file not found: %s\n', surface_roi_xml);
end

% 6. SAVE TO CSV
output_csv = fullfile(output_root, [subject_filename, '_cat12_results.csv']);
result_table = struct2table(result);
try
    writetable(result_table, output_csv);
    fprintf('Results saved to: %s\n', output_csv);
    fprintf('Total columns in CSV: %d\n', width(result_table));
catch ME
    fprintf('Error saving CSV: %s\n', ME.message);
    disp(getReport(ME));
end

fprintf('\n=== CAT12 surface analysis and ROI extraction completed successfully ===\n');
exit(0);