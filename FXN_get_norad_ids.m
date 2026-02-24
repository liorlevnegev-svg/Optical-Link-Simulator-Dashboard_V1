function [noradStr, noradVec] = FXN_get_norad_ids(requests, excelPath)
%FXN_GET_NORAD_IDS  Return NORAD IDs for one or multiple constellation/group requests.
%
% Inputs
%   requests  - string/char/cellstr/string array. Example:
%               "Tranche 0"
%               ["Tranche 0","Starlink (all)","6"]
%   excelPath - Excel catalogue path
%
% Output
%   noradStr  - space-separated string of NORAD IDs
%   noradVec  - row vector of unique NORAD IDs
%
% Side effect
%   Writes "norad_ids.txt" (one NORAD per line)

    % --- Default Arguments ---
    if nargin < 2 || strlength(string(excelPath)) == 0
        excelPath = "Optical Constellation Catalogue_Lior Lev.xlsx";
    end

    % --- File Check ---
    if ~isfile(excelPath)
        % Try searching on path
        w = which(excelPath);
        if ~isempty(w)
            excelPath = w;
        else
            error("FXN_get_norad_ids:CatalogueNotFound", ...
                "Excel catalogue not found at: %s", excelPath);
        end
    end

    % --- Normalize Requests ---
    % Ensure requests is a flat string row vector
    reqList = string(requests);
    reqList = reqList(:).';
    reqList = strip(reqList);

    % Default if empty
    if isempty(reqList) || all(strlength(reqList)==0)
        reqList = "Tranche 0";
    end

    sheetName = "OpticalCapableSatellites";

    % --- Read Excel Header ---
    % We read the raw cells first to find the header row dynamically
    try
        raw = readcell(excelPath, "Sheet", sheetName);
    catch ME
        error("FXN_get_norad_ids:ReadFailed", ...
            "Could not read sheet '%s' from file '%s'.\nError: %s", ...
            sheetName, excelPath, ME.message);
    end

    headerRow = findHeaderRow(raw);

    % --- Read Data Table ---
    opts = detectImportOptions(excelPath, "Sheet", sheetName, "VariableNamingRule","preserve");
    opts.VariableNamesRange = sprintf("%d:%d", headerRow, headerRow);
    opts.DataRange          = sprintf("%d:%d", headerRow+1, size(raw,1));
    
    % Force all columns to string/char initially to avoid NaN issues with mixed data
    opts = setvaropts(opts, opts.VariableNames, "Type", "string");
    
    T = readtable(excelPath, opts);
    T.Properties.VariableNames = strtrim(string(T.Properties.VariableNames));

    % --- Identify Columns ---
    colNORAD = findCol(T, ["NORAD","NORAD ID","NORAD_ID","NORADID"]);
    colConst = findCol(T, ["Constellation","Constellation Name","Group","Group Name"]);
    colOper  = findCol(T, ["Operator","Company","Owner"]);

    if strlength(colNORAD)==0 || strlength(colConst)==0
        error("FXN_get_norad_ids:MissingColumns", ...
            "Missing required columns (NORAD, Constellation Name) in sheet '%s'. Found headers: %s", ...
            sheetName, strjoin(string(T.Properties.VariableNames),", "));
    end

    % --- Parse Data ---
    noradNum = toNumericNORAD(T.(colNORAD));
    constell = string(T.(colConst));

    if strlength(colOper) > 0
        oper = string(T.(colOper));
    else
        oper = strings(size(constell));
    end

    % Filter out invalid NORADs (NaN or <= 0)
    valid = noradNum > 0 & ~isnan(noradNum);
    noradNum = noradNum(valid);
    constell = constell(valid);
    oper     = oper(valid);

    % --- Common Helper Masks ---
    operL     = lower(oper);
    constellL = lower(constell);

    isStarlink = contains(operL, "spacex") | contains(constellL, "starlink");
    isKepler   = contains(operL, "kepler");
    isSDA      = contains(operL, "space development agency") | contains(operL, "sda") | contains(constellL, "tranche");
    isAmazon   = contains(operL, "amazon") | contains(constellL, "kuiper") | contains(constellL, "amazon");

    maskAll = false(size(noradNum));

    % --- Process Requests ---
    for r = reqList
        req = lower(strtrim(string(r)));
        mask = false(size(noradNum));

        if req == "" 
            continue; 
        end

        switch req
            case {"kepler aether","aether"}
                mask = contains(constellL,"aether") | isKepler;

            case {"sda"}
                mask = isSDA;

            case {"tranche 0","tranch 0"} 
                mask = contains(constellL, "tranche 0");

            case {"tranche 1","tranch 1"}
                mask = contains(constellL, "tranche 1");

            case {"amazon leo","amazon","leo"}
                mask = isAmazon;

            case {"starlink (all)","starlink all","starlink"}
                mask = isStarlink;

            case {"esa spacedatahighwaynetwork","space data highway","spacedatahighwaynetwork"}
                mask = contains(constellL,"spacedatahighway") | contains(constellL,"space data highway") | contains(operL,"esa");

            case {"eutelsat 9b"}
                mask = contains(constellL,"eutelsat 9b") | contains(operL,"eutelsat");

            case {"edrs-c","edrs c"}
                mask = contains(constellL,"edrs-c") | contains(constellL,"edrs c");

            otherwise
                % Numeric Starlink group selections: "6", "7", "10", "17" etc.
                if ~isempty(regexp(req,"^\d+$","once"))
                    % select Starlink entries whose group starts with "<n>-" or is exactly <n>
                    mask = isStarlink & (startsWith(constellL, req + "-") | constellL == req);
                elseif ~isempty(regexp(req,"^\d+\-\d+$","once"))
                    % specific mission like "6-1"
                    mask = isStarlink & contains(constellL, req);
                else
                    % Fallback: try generic contains match
                    mask = contains(constellL, req) | contains(operL, req);
                end
        end

        maskAll = maskAll | mask;
    end

    % --- Output Generation ---
    noradVec = unique(noradNum(maskAll)).';
    noradStr = strtrim(sprintf("%.0f ", noradVec));

    % --- Write File ---
    fid = fopen("norad_ids.txt","w");
    if fid < 0
        warning("FXN_get_norad_ids:FileWriteFailed", "Could not open norad_ids.txt for writing.");
    else
        fprintf(fid,"%.0f\n",noradVec);
        fclose(fid);
    end

    % Console summary
    fprintf("\n[FXN_get_norad_ids] Requests: %s\n -> Found %d satellites.\n", ...
        strjoin(reqList,", "), numel(noradVec));
end

% ================= LOCAL FUNCTIONS =================

function headerRow = findHeaderRow(raw)
    % Pick the first row that contains "norad" anywhere
    % Convert raw cell array to string for searching
    s = string(raw);
    % Make case insensitive
    s = lower(s);
    
    % Handle missing/NaN
    s(ismissing(s)) = ""; 
    
    % Find row with "norad" and "constellation" or just "norad"
    hasNorad = any(contains(s, "norad"), 2);
    
    headerRow = find(hasNorad, 1, 'first');
    
    if isempty(headerRow)
        warning("Could not automatically find header row containing 'NORAD'. Defaulting to row 1.");
        headerRow = 1;
    end
end

function col = findCol(T,names)
    hdr = string(T.Properties.VariableNames);
    hdrL = lower(hdr);
    col = "";
    for n = names
        nL = lower(string(n));
        idx = find(strcmp(hdrL, nL), 1); % Try exact match first
        if isempty(idx)
             idx = find(contains(hdrL, nL), 1); % Try partial match
        end
        
        if ~isempty(idx)
            col = hdr(idx);
            return;
        end
    end
end

function num = toNumericNORAD(x)
    x = string(x);
    % Remove non-numeric characters (except keeping dots might be risky for IDs, but usually IDs are integers)
    x = regexprep(x,"[^\d]",""); 
    num = str2double(x);
end