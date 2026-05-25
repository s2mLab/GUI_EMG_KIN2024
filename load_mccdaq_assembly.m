function assemblyPath = load_mccdaq_assembly()
%LOAD_MCCDAQ_ASSEMBLY Load the MCC Universal Library .NET assembly on Windows.
%   If MccDaq is not registered in the .NET GAC, load the installed DLL by
%   absolute path instead.

    if ~ispc
        error(['MccDaq est disponible uniquement sur un poste Windows avec ' ...
            'Measurement Computing Universal Library installee.']);
    end

    gacError = '';
    try
        NET.addAssembly('MccDaq');
        assemblyPath = 'Global Assembly Cache (MccDaq)';
        return
    catch ME
        gacError = ME.message;
    end

    candidates = {
        fullfile(getenv('MCCDAQ_DIR'), 'MccDaq.dll')
        fullfile(getenv('ProgramFiles'), 'Measurement Computing', 'DAQ', 'MccDaq.dll')
        fullfile(getenv('ProgramFiles(x86)'), 'Measurement Computing', 'DAQ', 'MccDaq.dll')
        'C:\Program Files\Measurement Computing\DAQ\MccDaq.dll'
        'C:\Program Files (x86)\Measurement Computing\DAQ\MccDaq.dll'
    };

    for i = 1:numel(candidates)
        candidate = candidates{i};
        if ~isempty(candidate) && isfile(candidate)
            NET.addAssembly(candidate);
            assemblyPath = candidate;
            fprintf('MccDaq charge depuis : %s\n', assemblyPath);
            return
        end
    end

    searched = strjoin(candidates(~cellfun(@isempty, candidates)), newline);
    error(['MccDaq.dll introuvable. Installez Measurement Computing ' ...
        'Universal Library for .NET, puis executez InstaCal. ' ...
        'Chemins verifies :' newline '%s' newline ...
        'Erreur de recherche dans le GAC : %s'], searched, gacError);
end
