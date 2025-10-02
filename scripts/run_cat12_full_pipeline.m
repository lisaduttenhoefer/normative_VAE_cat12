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

% Prepare CAT12 batch
matlabbatch = {};
matlabbatch{1}.spm.tools.cat.estwrite.data{1} = subject_path;

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

% QC Report Generation
matlabbatch{1}.spm.tools.cat.estwrite.extopts.print = 2;

% Surface outputs - für DK Thickness & Gyrification
matlabbatch{1}.spm.tools.cat.estwrite.output.surface = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.surf_measures = 1;

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

% CRITICAL: Aktiviere alle gewünschten Atlanten
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.lpba40 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.cobra = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.hammers = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.ibsr = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.aal3 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.mori = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.anatomy3 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.julichbrain = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.Schaefer2018_100Parcels_17Networks_order = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.Schaefer2018_200Parcels_17Networks_order = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.Schaefer2018_400Parcels_17Networks_order = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.Schaefer2018_600Parcels_17Networks_order = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.atlases.ownatlas = {''};

% Run CAT12
try
    spm_jobman('run', matlabbatch);
    fprintf('CAT12 processing completed successfully\n');
catch ME
    fprintf('Error during CAT12 processing: %s\n', ME.message);
    disp(getReport(ME));
    exit(1);
end

% =========================================================================
% POST-PROCESSING: Extract all metrics
% =========================================================================
fprintf('\n=== Starting data extraction ===\n');

[subject_dir, subject_filename, ~] = fileparts(subject_path);

report_dir = fullfile(subject_dir, 'report');
label_dir = fullfile(subject_dir, 'label');
surf_dir = fullfile(subject_dir, 'surf');

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
    result.IQR = NaN; result.NCR = NaN; result.ICR = NaN; 
    result.res_RMS = NaN; result.TIV = NaN; result.GM_vol = NaN; 
    result.WM_vol = NaN; result.CSF_vol = NaN; result.WMH_vol = NaN;
end

% 2. CORTICAL THICKNESS (nur DK)
lh_thick = fullfile(surf_dir, ['lh.thickness.', subject_filename]);
rh_thick = fullfile(surf_dir, ['rh.thickness.', subject_filename]);
if exist(lh_thick, 'file') && exist(rh_thick, 'file')
    try
        lh_data = cat_io_FreeSurfer('read_surf_data', lh_thick);
        rh_data = cat_io_FreeSurfer('read_surf_data', rh_thick);
        result.mean_thickness_lh = mean(lh_data, 'omitnan');
        result.mean_thickness_rh = mean(rh_data, 'omitnan');
        result.mean_thickness_global = mean([lh_data; rh_data], 'omitnan');
        fprintf('Thickness extracted\n');
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

% 3. GYRIFICATION (nur DK)
lh_gyri = fullfile(surf_dir, ['lh.gyrification.', subject_filename]);
rh_gyri = fullfile(surf_dir, ['rh.gyrification.', subject_filename]);
if exist(lh_gyri, 'file') && exist(rh_gyri, 'file')
    try
        lh_data = cat_io_FreeSurfer('read_surf_data', lh_gyri);
        rh_data = cat_io_FreeSurfer('read_surf_data', rh_gyri);
        result.mean_gyri_lh = mean(lh_data, 'omitnan');
        result.mean_gyri_rh = mean(rh_data, 'omitnan');
        result.mean_gyri_global = mean([lh_data; rh_data], 'omitnan');
        fprintf('Gyrification extracted\n');
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

% 4. ROI EXTRACTION - NUR FÜR AKTUELLEN PATIENTEN
roi_file = fullfile(label_dir, ['catROI_', subject_filename, '.xml']);

if exist(roi_file, 'file')
    try
        roi_data = cat_io_xml(roi_file);
        
        % Liste der Atlanten die wir wollen
        atlases_to_extract = {'neuromorphometrics', 'lpba40', 'cobra', 'aparc_DK40', 'suit'};
        
        for atlas_idx = 1:length(atlases_to_extract)
            atlas_name = atlases_to_extract{atlas_idx};
            
            % Check if this atlas exists in the data
            if ~isfield(roi_data, atlas_name)
                fprintf('Warning: Atlas %s not found in XML\n', atlas_name);
                continue;
            end
            
            atlas_struct = roi_data.(atlas_name);
            
            % Extract names - can be in different formats
            if isfield(atlas_struct, 'names')
                if isstruct(atlas_struct.names)
                    % names is a struct with 'item' field
                    if isfield(atlas_struct.names, 'item')
                        if iscell(atlas_struct.names.item)
                            roi_names = atlas_struct.names.item;
                        else
                            roi_names = {atlas_struct.names.item};
                        end
                    else
                        fprintf('Warning: Cannot parse names for %s\n', atlas_name);
                        continue;
                    end
                elseif iscell(atlas_struct.names)
                    roi_names = atlas_struct.names;
                else
                    fprintf('Warning: Unexpected names format for %s\n', atlas_name);
                    continue;
                end
            else
                fprintf('Warning: No names field for %s\n', atlas_name);
                continue;
            end
            
            % Extract volumes (Vgm)
            if isfield(atlas_struct, 'Vgm')
                roi_volumes = atlas_struct.Vgm;
            else
                roi_volumes = [];
            end
            
            % Extract thickness (nur für DK)
            if strcmp(atlas_name, 'aparc_DK40') && isfield(atlas_struct, 'thickness')
                roi_thickness = atlas_struct.thickness;
            else
                roi_thickness = [];
            end
            
            % Extract gyrification (nur für DK)
            if strcmp(atlas_name, 'aparc_DK40') && isfield(atlas_struct, 'gyrification')
                roi_gyrification = atlas_struct.gyrification;
            else
                roi_gyrification = [];
            end
            
            % Add to result structure
            for r = 1:length(roi_names)
                roi_name = roi_names{r};
                roi_name_clean = matlab.lang.makeValidName([atlas_name, '_', roi_name]);
                
                % Volumes
                if r <= length(roi_volumes)
                    result.(['Vol_', roi_name_clean]) = roi_volumes(r);
                end
                
                % Thickness (nur DK)
                if r <= length(roi_thickness)
                    result.(['Thick_', roi_name_clean]) = roi_thickness(r);
                end
                
                % Gyrification (nur DK)
                if r <= length(roi_gyrification)
                    result.(['Gyri_', roi_name_clean]) = roi_gyrification(r);
                end
            end
            
            fprintf('Extracted %s atlas (%d regions)\n', atlas_name, length(roi_names));
        end
        
    catch ME
        fprintf('Warning: Error reading ROI file: %s\n', ME.message);
        disp(getReport(ME));
    end
else
    fprintf('Warning: ROI file not found: %s\n', roi_file);
end

% 5. SAVE TO CSV
output_csv = fullfile(output_root, [subject_filename, '_cat12_results.csv']);
result_table = struct2table(result, 'AsArray', true);
try
    writetable(result_table, output_csv);
    fprintf('Results saved to: %s\n', output_csv);
catch ME
    fprintf('Error saving CSV: %s\n', ME.message);
end

fprintf('\n=== CAT12 surface analysis and ROI extraction completed successfully ===\n');
exit(0);