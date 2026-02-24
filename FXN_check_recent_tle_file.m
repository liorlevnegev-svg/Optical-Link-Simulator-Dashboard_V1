function [useExisting, existingFile] = FXN_check_recent_tle_file(request, maxAgeDays)
% check_recent_tle_file
% Checks if a TLE file for this request exists within maxAgeDays.
%
% Returns:
%   useExisting  -> true if valid recent file found
%   existingFile -> filename to reuse (empty if none)

    if nargin < 2
        maxAgeDays = 14; % default = 2 weeks
    end

    request = strtrim(string(request));
    group   = classify_request(request);
    safeReq = sanitize_filename(request);

    pattern = sprintf('%s_%s_*.txt', char(group), char(safeReq));
    files = dir(pattern);

    useExisting = false;
    existingFile = "";

    if isempty(files)
        return
    end

    todayDate = datetime("today");

    for i = 1:length(files)
        fname = files(i).name;

        % Extract yyyy-mm-dd from filename
        tokens = regexp(fname, '\d{4}-\d{2}-\d{2}', 'match');

        if isempty(tokens)
            continue
        end

        fileDate = datetime(tokens{1}, 'InputFormat','yyyy-MM-dd');

        if days(todayDate - fileDate) <= maxAgeDays
            useExisting = true;
            existingFile = fname;
            return
        end
    end
end


%% Helper functions (copy these exactly from your main script)

function group = classify_request(request)
    r = upper(strtrim(char(request)));
    nums   = regexp(r, '(?<!\d)([6-9]|1[0-7])(?!\d)', 'match');
    dashed = regexp(r, '(?<!\d)([6-9]|1[0-7])-\d+', 'match');
    if ~isempty(nums) || ~isempty(dashed), group = "STARLINK"; return; end
    if contains(r, "TRANCHE"), group = "SDA"; return; end
    if contains(r, "LEO"), group = "AMAZON"; return; end
    if contains(r, "AETHER"), group = "KEPLER"; return; end
    group = "BLIND";
end

function s = sanitize_filename(s)
    s = string(s);
    s = strrep(s, " ", "-");
    s = regexprep(s, '[^A-Za-z0-9\-_]', '');
    if strlength(s) == 0, s = "REQUEST"; end
end
