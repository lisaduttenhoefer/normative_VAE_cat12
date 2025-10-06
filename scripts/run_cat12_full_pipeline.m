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

% Nur die gewünschten Atlanten aktivieren
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.neuromorphometrics = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.lpba40 = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.cobra = 1;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.hammers = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ibsr = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.thalamus = 0;
matlabbatch{1}.spm.tools.cat.estwrite.output.ROImenu.atlases.ownatlas = {''};

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

% CAT12 creates subdirectories in the same location as the input file
surf_dir = fullfile(output_root, 'surf');
label_dir = fullfile(output_root, 'label');
report_dir = fullfile(output_root, 'report');

% Check if thickness files exist
lh_thick = fullfile(surf_dir, ['lh.thickness.', subject_filename]);
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

% 4. ROI EXTRACTION - Volume atlases (explizit definiert)
roi_file = fullfile(label_dir, ['catROI_', subject_filename, '.xml']);

% Liste der gewünschten Atlanten - muss mit CAT12 Konfiguration übereinstimmen
desired_atlases = {'neuromorphometrics', 'lpba40', 'cobra', 'suit'};

if exist(roi_file, 'file')
    try
        roi_data = cat_io_xml(roi_file);
        
        for atlas_idx = 1:length(desired_atlases)
            atlas_name = desired_atlases{atlas_idx};
            
            % Check if this atlas exists in the data
            if ~isfield(roi_data, atlas_name)
                fprintf('Warning: Atlas %s not found in XML (möglicherweise nicht von CAT12 generiert)\n', atlas_name);
                continue;
            end
            
            atlas_struct = roi_data.(atlas_name);
            
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
            
            % Extract volumes (Vgm) - check both possible locations
            if isfield(atlas_struct, 'data') && isfield(atlas_struct.data, 'Vgm')
                roi_volumes = atlas_struct.data.Vgm;
            elseif isfield(atlas_struct, 'Vgm')
                roi_volumes = atlas_struct.Vgm;
            else
                roi_volumes = [];
            end
            
            % Kürze Atlas-Namen für CSV
            atlas_name_short = atlas_name;
            if strcmp(atlas_name, 'neuromorphometrics')
                atlas_name_short = 'Neurom';
            end
            
            % Add to result structure mit kürzerem Präfix
            for r = 1:length(roi_names)
                roi_name = roi_names{r};
                roi_name_clean = matlab.lang.makeValidName([atlas_name_short, '_', roi_name]);
                
                if r <= length(roi_volumes)
                    result.(['V_', roi_name_clean]) = roi_volumes(r);
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
            
            % Extract thickness if available (mit kürzerem Präfix T_)
            if isfield(atlas_struct, 'data') && isfield(atlas_struct.data, 'thickness')
                roi_thickness = atlas_struct.data.thickness;
                
                for r = 1:length(roi_names)
                    roi_name_clean = matlab.lang.makeValidName([atlas_name, '_', roi_names{r}]);
                    if r <= length(roi_thickness)
                        result.(['T_', roi_name_clean]) = roi_thickness(r);
                    end
                end
                
                fprintf('Extracted %s thickness (%d regions)\n', atlas_name, length(roi_names));
            end
            
            % Extract gyrification if available (mit kürzerem Präfix G_)
            if isfield(atlas_struct, 'data') && isfield(atlas_struct.data, 'gyrification')
                roi_gyri = atlas_struct.data.gyrification;
                
                for r = 1:length(roi_names)
                    roi_name_clean = matlab.lang.makeValidName([atlas_name, '_', roi_names{r}]);
                    if r <= length(roi_gyri)
                        result.(['G_', roi_name_clean]) = roi_gyri(r);
                    end
                end
                
                fprintf('Extracted %s gyrification (%d regions)\n', atlas_name, length(roi_names));
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