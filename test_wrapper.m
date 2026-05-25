[~, user] = system('echo %USERNAME%');
user = strtrim(user);

pathsToCheck = {
    'C:\Program Files\Measurement Computing\DAQ'
    'C:\Program Files (x86)\Measurement Computing\DAQ'
    fullfile('C:\Users',user,'Documents')
};

for i=1:numel(pathsToCheck)
    p = pathsToCheck{i};
    if isfolder(p)
        files = dir(fullfile(p,'**','MccDaq.dll'));
        if ~isempty(files)
            disp("MccDaq.dll trouvée dans: " + files(1).folder);
            disp({files.name}');
        end
    end
end
