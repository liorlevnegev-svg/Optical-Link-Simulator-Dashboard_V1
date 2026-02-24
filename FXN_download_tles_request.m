function outFile = FXN_download_tles_request(request, noradTxtPath)
% download_tles_request
% - Reads NORAD IDs from norad_ids.txt
% - Classifies request into STARLINK / SDA / AMAZON / KEPLER / BLIND
% - Downloads TLEs from Space-Track using HTTP Basic Auth header
% - Saves: Group_Request_NumberOfSatellites_yyyy-mm-dd.txt
% - File content: NAME + line1 + line2 (blank line)

    if nargin < 2 || strlength(string(noradTxtPath)) == 0
        noradTxtPath = "norad_ids.txt";
    end

    request = strtrim(string(request));
    noradTxtPath = string(noradTxtPath);

    %% ===================== YOU MUST EDIT THIS =====================
    username = "100562471@alumnos.uc3m.es";
    password = "bCg_FU-jrPj9aU!";
    %% =============================================================

if ~isfile(noradTxtPath)
        error(sprintf('Could not find norad IDs file: %s', char(noradTxtPath)));
    end
    if strcmp(username, "YOUR_SPACETRACK_USERNAME") || strcmp(password, "YOUR_SPACETRACK_PASSWORD")
        error('Set your Space-Track credentials at the top of download_tles_request.m');
    end

    group  = classify_request(request);
    norads = read_norads_from_txt(noradTxtPath);
    if isempty(norads)
        error(sprintf('No NORAD IDs found in %s', char(noradTxtPath)));
    end

    % ---- Login and get cookies ----
    cookies = spacetrack_java_login(username, password);

    % ---- Fetch TLE text in chunks ----
    chunkSize = 300; % conservative URL length
    allBlocks = {};
    n = numel(norads);

    for k = 1:chunkSize:n
        ids = norads(k:min(k+chunkSize-1, n));
        idStr = strjoin(cellstr(string(ids)), ",");

        % Try gp_latest
        path1 = ['/basicspacedata/query/' ...
                 'class/gp_latest/NORAD_CAT_ID/' idStr ...
                 '/format/3le'];


        [code, body] = spacetrack_java_get(['https://www.space-track.org' path1], cookies);

        if code == 204 || isempty(strtrim(body))
            % Fallback to gp ordered by epoch desc
        path2 = ['/basicspacedata/query/' ...
                 'class/gp/NORAD_CAT_ID/' idStr ...
                 '/orderby/EPOCH%20desc' ...
                 '/format/3le'];


            [code2, body2] = spacetrack_java_get(['https://www.space-track.org' path2], cookies);

            if code2 == 204 || isempty(strtrim(body2))
                fprintf("Chunk starting %d: no TLE records (204).\n", k);
                continue;
            end

            if code2 ~= 200
                prev = body2; if numel(prev) > 300, prev = prev(1:300); end
                error(sprintf('Space-Track gp fallback HTTP %d on chunk %d. Preview:\n%s', code2, k, prev));
            end

            blocks = parse_3le_blocks(string(body2));
        else
            if code ~= 200
                prev = body; if numel(prev) > 300, prev = prev(1:300); end
                error(sprintf('Space-Track HTTP %d on chunk %d. Preview:\n%s', code, k, prev));
            end

            blocks = parse_3le_blocks(string(body));
        end

        if ~isempty(blocks)
            allBlocks = [allBlocks; blocks]; %#ok<AGROW>
        end
    end

    if isempty(allBlocks)
        error('No TLE blocks parsed. If login succeeded, these NORADs may not have GP data yet.');
    end

    % Keep only valid 1/2 lines
    ok = false(size(allBlocks,1),1);
    for i = 1:size(allBlocks,1)
        ok(i) = startsWith(strtrim(string(allBlocks{i,2})), "1 ") && ...
                startsWith(strtrim(string(allBlocks{i,3})), "2 ");
    end
    allBlocks = allBlocks(ok,:);
    numSats = size(allBlocks, 1);

    safeReq = sanitize_filename(request);
    dateStr = char(datetime("today","Format","yyyy-MM-dd"));
    outFile = sprintf('%s_%s_%d_%s.txt', char(group), char(safeReq), numSats, dateStr);

    % Write output
    fid = fopen(outFile, "w");
    if fid <= 0
        error(sprintf('Could not open output file: %s', outFile));
    end
    c = onCleanup(@() fclose(fid));

    for i = 1:numSats
        fprintf(fid, "%s\n%s\n%s\n\n", ...
            char(allBlocks{i,1}), char(allBlocks{i,2}), char(allBlocks{i,3}));
    end

    fprintf("Saved %d TLEs to: %s\n", numSats, outFile);
end

%% ===================== Java: login =====================
function cookies = spacetrack_java_login(username, password)
    loginUrl = 'https://www.space-track.org/ajaxauth/login';

    postData = sprintf('identity=%s&password=%s', urlenc(char(username)), urlenc(char(password)));

    [code, ~, setCookies, body] = java_http_request(loginUrl, 'POST', postData, '');

    if code ~= 200
        prev = body; if numel(prev) > 300, prev = prev(1:300); end
        error(sprintf('Space-Track login HTTP %d. Preview:\n%s', code, prev));
    end

    % Build "Cookie: a=b; c=d" from Set-Cookie headers
    cookies = build_cookie_string(setCookies);

    if isempty(cookies)
        prev = body; if numel(prev) > 300, prev = prev(1:300); end
        error(sprintf('Login returned no cookies. Preview:\n%s', prev));
    end
end

%% ===================== Java: GET =====================
function [code, body] = spacetrack_java_get(url, cookies)
    [code, ~, ~, body] = java_http_request(url, 'GET', '', cookies);
end

%% ===================== Core Java HTTP helper =====================
function [code, headers, setCookies, body] = java_http_request(urlStr, method, postData, cookies)
    import java.net.URL
    import java.net.HttpURLConnection
    import java.io.*

    url = URL(urlStr);
    conn = url.openConnection();
    conn.setInstanceFollowRedirects(true);
    conn.setRequestMethod(method);

    % headers
    conn.setRequestProperty('User-Agent', 'MATLAB Space-Track Client');
    conn.setRequestProperty('Accept', '*/*');

    if ~isempty(cookies)
        conn.setRequestProperty('Cookie', cookies);
    end

    if strcmpi(method, 'POST')
        conn.setDoOutput(true);
        conn.setRequestProperty('Content-Type', 'application/x-www-form-urlencoded');
        conn.setRequestProperty('Charset', 'utf-8');

        os = conn.getOutputStream();
        os.write(uint8(postData));
        os.flush();
        os.close();
    end

    code = conn.getResponseCode();

    % Collect headers
    headers = conn.getHeaderFields();

    % Collect Set-Cookie values (may be multiple)
    setCookies = {};
    try
        sc = conn.getHeaderFields().get('Set-Cookie');
        if ~isempty(sc)
            it = sc.iterator();
            while it.hasNext()
                setCookies{end+1} = char(it.next()); %#ok<AGROW>
            end
        end
    catch
        % ignore
    end

    % Read body
    try
        if code >= 400
            stream = conn.getErrorStream();
        else
            stream = conn.getInputStream();
        end

        if isempty(stream)
            body = '';
        else
            reader = BufferedReader(InputStreamReader(stream));
            sb = java.lang.StringBuilder();
            line = reader.readLine();
            while ~isempty(line)
                sb.append(line);
                sb.append(char(10));
                line = reader.readLine();
            end
            reader.close();
            body = char(sb.toString());
        end
    catch
        body = '';
    end

    conn.disconnect();
end

function cookieStr = build_cookie_string(setCookies)
    % setCookies is cell array of strings like: "cookie=value; Path=/; ..."
    parts = {};
    for i = 1:numel(setCookies)
        v = setCookies{i};
        semi = strfind(v, ';');
        if isempty(semi)
            kv = strtrim(v);
        else
            kv = strtrim(v(1:semi(1)-1));
        end
        if ~isempty(kv)
            parts{end+1} = kv; %#ok<AGROW>
        end
    end
    cookieStr = strjoin(parts, '; ');
end

function s = urlenc(s)
    % Minimal x-www-form-urlencoded encoding
    s = strrep(s, '%', '%25');
    s = strrep(s, ' ', '%20');
    s = strrep(s, '!', '%21');
    s = strrep(s, '"', '%22');
    s = strrep(s, '#', '%23');
    s = strrep(s, '$', '%24');
    s = strrep(s, '&', '%26');
    s = strrep(s, '''', '%27');
    s = strrep(s, '(', '%28');
    s = strrep(s, ')', '%29');
    s = strrep(s, '*', '%2A');
    s = strrep(s, '+', '%2B');
    s = strrep(s, ',', '%2C');
    s = strrep(s, '/', '%2F');
    s = strrep(s, ':', '%3A');
    s = strrep(s, ';', '%3B');
    s = strrep(s, '=', '%3D');
    s = strrep(s, '?', '%3F');
    s = strrep(s, '@', '%40');
    s = strrep(s, '[', '%5B');
    s = strrep(s, ']', '%5D');
end

%% ===================== Existing helpers =====================
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

function norads = read_norads_from_txt(path)
    raw = readlines(path);
    raw = strip(raw);
    raw = raw(raw ~= "");
    ids = zeros(0,1);
    for i = 1:numel(raw)
        tok = regexp(char(raw(i)), '\d+', 'match', 'once');
        if ~isempty(tok)
            ids(end+1,1) = str2double(tok); %#ok<AGROW>
        end
    end
    norads = unique(ids(~isnan(ids) & ids > 0));
end

function blocks = parse_3le_blocks(tleText)
    lines = splitlines(string(tleText));
    lines = strip(lines);
    lines = lines(lines ~= "");

    blocks = {};
    i = 1;

    while i <= numel(lines)

        % --- Case A: 3LE: [NAME, line1, line2]
        if i+2 <= numel(lines) && ...
           ~startsWith(lines(i),"1 ") && ~startsWith(lines(i),"2 ") && ...
            startsWith(lines(i+1),"1 ") && startsWith(lines(i+2),"2 ")

name = strtrim(lines(i));

            % Remove leading "0 " if present
            if startsWith(name, "0 ")
                name = extractAfter(name, 2);
            end
            
            blocks(end+1,:) = {char(name), char(lines(i+1)), char(lines(i+2))}; %#ok<AGROW>

            i = i + 3;
            continue
        end

        % --- Case B: 2LE: [line1, line2] (no name given)
        if i+1 <= numel(lines) && startsWith(lines(i),"1 ") && startsWith(lines(i+1),"2 ")
            % NORAD is columns 3-7 in TLE line 1
            norad = extractBetween(lines(i), 3, 7);
            name  = "NORAD_" + string(norad);   % fallback label only
            blocks(end+1,:) = {char(name), char(lines(i)), char(lines(i+1))}; %#ok<AGROW>
            i = i + 2;
            continue
        end

        i = i + 1;
    end
end


function s = sanitize_filename(s)
    s = string(s);
    s = strrep(s, " ", "-");
    s = regexprep(s, '[^A-Za-z0-9\-_]', '');
    if strlength(s) == 0, s = "REQUEST"; end
end