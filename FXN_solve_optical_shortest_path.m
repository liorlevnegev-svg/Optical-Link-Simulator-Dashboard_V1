function result = FXN_solve_optical_shortest_path(cfg)
%SOLVE_OPTICAL_SHORTEST_PATH Optical relay shortest path solver (callable).
%
% result = solve_optical_shortest_path(cfg)
%
% cfg fields required:
%   inFile (string)
%   startLLA (1x3) [lat lon alt_m]
%   endLLA   (1x3)
%   maxDTE_km, maxISL_km, minElevation_deg
%   sampleTime_s, numberAttempts
%   t0 (datetime, TimeZone='UTC')
%
% cfg optional:
%   outTxt (default "optical_link_hops.txt")
%   plotWindow_minutes (default 30)
%   make3DScenarioViewer (default true)
%   make2DMapFigure (default true)
%   mapBasemap (default "colorterrain")
%   verbose (default true)
%
% Outputs in "result":
%   solved (logical)
%   status (string)
%   elapsed_s (double)
%   tUse (datetime)
%   HopTable (table)
%   usedSatNames (string array)
%   usedSatIdx (double array, indices into loaded satCells)
%   satLoadSummary (struct)

tStartTotal = tic;

% ---------------- defaults ----------------
cfg = applyDefaults(cfg);

result = struct();
result.solved = false;
result.status = "Not started";
result.elapsed_s = NaN;
result.tUse = cfg.t0;
result.HopTable = table();
result.usedSatNames = strings(0,1);
result.usedSatIdx = [];
result.satLoadSummary = struct();

try
    %% =========================
    %  1) IMPORT TLEs + LOAD SATELLITES
    %  =========================
    [names, L1, L2] = parseTLEFile(cfg.inFile);

    if cfg.verbose
        fprintf("Parsed %d candidate satellites from TLE file.\n", numel(names));
    end

    if isempty(names)
        error("No valid TLE blocks found in %s", cfg.inFile);
    end

    % Scenario only for states() calls across attempted times
    tStop = cfg.t0 + seconds(cfg.sampleTime_s*(cfg.numberAttempts-1)) + minutes(2);
    scAll = satelliteScenario(cfg.t0 - minutes(2), tStop, max(1, min(cfg.sampleTime_s,60)));

    % Load satellites best-effort
    [satCells, satTleIdx, loadWarnings] = loadSatellitesFromTLE(scAll, names, L1, L2);

    Ns = numel(satCells);
    if cfg.verbose
        fprintf("Loaded %d/%d satellites successfully into satelliteScenario.\n", Ns, numel(names));
    end
    if Ns == 0
        error("No satellites could be loaded. Check TLE formatting/toolbox availability.");
    end

    result.satLoadSummary.totalTLEBlocks = numel(names);
    result.satLoadSummary.loadedSatellites = Ns;
    result.satLoadSummary.skippedWarnings = loadWarnings;

    %% =========================
    %  2) CONVERT START/END TO ECEF
    %  =========================
    rGS_start_ecef = lla2ecef_wgs84(cfg.startLLA);
    rGS_end_ecef   = lla2ecef_wgs84(cfg.endLLA);

    if cfg.verbose
        fprintf("Start GS (LLA): [%.4f, %.4f, %.1f m]\n", cfg.startLLA(1), cfg.startLLA(2), cfg.startLLA(3));
        fprintf("End   GS (LLA): [%.4f, %.4f, %.1f m]\n", cfg.endLLA(1),   cfg.endLLA(2),   cfg.endLLA(3));
    end

    %% =========================
    %  3) ATTEMPT TIME SEARCH (FORWARD IN TIME)
    %  =========================
    Re_m     = 6378137.0;
    maxDTE_m = cfg.maxDTE_km * 1e3;
    maxISL_m = cfg.maxISL_km * 1e3;

    solved = false;
    tUse = cfg.t0;

    satNames = strings(Ns,1);
    rSat_ecef = zeros(Ns,3);
    vSat_ecef = zeros(Ns,3);

    startSatIdx = NaN;
    endSatIdx   = NaN;
    pathSatIdx  = [];

    for attempt = 1:cfg.numberAttempts
        tTry = cfg.t0 + seconds((attempt-1) * cfg.sampleTime_s);
        if cfg.verbose
            fprintf("\nAttempt %d/%d at t = %s\n", attempt, cfg.numberAttempts, string(tTry));
        end

        [satNames, rSat_ecef, vSat_ecef, okMask] = computeSatStatesECEF(satCells, tTry);

        if cfg.verbose
            fprintf("Computed ECEF states for %d/%d loaded satellites.\n", sum(okMask), Ns);
        end
        if sum(okMask) == 0
            continue;
        end

        [startSatIdx, dteInfoStart] = pickNearestDTE( ...
            rGS_start_ecef, cfg.startLLA, rSat_ecef, okMask, maxDTE_m, cfg.minElevation_deg);

        [endSatIdx, dteInfoEnd] = pickNearestDTE( ...
            rGS_end_ecef, cfg.endLLA, rSat_ecef, okMask, maxDTE_m, cfg.minElevation_deg);

        if isnan(startSatIdx)
            if cfg.verbose
                fprintf("  DTE FAIL (START): No sat within %.0f km and el >= %.1f deg\n", cfg.maxDTE_km, cfg.minElevation_deg);
            end
            continue;
        else
            if cfg.verbose
                fprintf("  DTE OK (START): %s | dist=%.1f km | el=%.1f deg\n", satNames(startSatIdx), dteInfoStart.dist_m/1e3, dteInfoStart.el_deg);
            end
        end

        if isnan(endSatIdx)
            if cfg.verbose
                fprintf("  DTE FAIL (END):   No sat within %.0f km and el >= %.1f deg\n", cfg.maxDTE_km, cfg.minElevation_deg);
            end
            continue;
        else
            if cfg.verbose
                fprintf("  DTE OK (END):   %s | dist=%.1f km | el=%.1f deg\n", satNames(endSatIdx), dteInfoEnd.dist_m/1e3, dteInfoEnd.el_deg);
            end
        end

        pathSatIdx = shortestPathISL(rSat_ecef, okMask, startSatIdx, endSatIdx, maxISL_m, Re_m);
        if isempty(pathSatIdx)
            if cfg.verbose
                fprintf("  ISL FAIL: No route within maxISL_km=%.0f km.\n", cfg.maxISL_km);
            end
            continue;
        end

        solved = true;
        tUse = tTry;
        if cfg.verbose
            fprintf("  ISL OK: Found path with %d satellites.\n", numel(pathSatIdx));
        end
        break;
    end

    if ~solved
        result.solved = false;
        result.status = sprintf("No links available now and for next %d samples (step %.0f s).", cfg.numberAttempts, cfg.sampleTime_s);
        result.elapsed_s = toc(tStartTotal);
        return;
    end

    %% =========================
    %  4) PRUNE ARRAYS TO USED SATELLITES ONLY
    %  =========================
    usedSatIdx = unique(pathSatIdx(:), "stable");

    satNames_used  = satNames(usedSatIdx);
    rSat_used_ecef = rSat_ecef(usedSatIdx,:);
    vSat_used_ecef = vSat_ecef(usedSatIdx,:);

    Nu = numel(usedSatIdx);
    origToCompact = containers.Map('KeyType','double','ValueType','double');
    for k = 1:Nu
        origToCompact(usedSatIdx(k)) = k;
    end
    pathCompact = zeros(size(pathSatIdx));
    for k = 1:numel(pathSatIdx)
        pathCompact(k) = origToCompact(pathSatIdx(k));
    end

    %% =========================
    %  5) BUILD HOP TABLE + EXPORT
    %  =========================
    HopNodes = ["GS_START"; satNames_used(pathCompact); "GS_END"];

    rNodes_ecef = zeros(numel(HopNodes), 3);
    vNodes_ecef = zeros(numel(HopNodes), 3);

    rNodes_ecef(1,:) = rGS_start_ecef;
    vNodes_ecef(1,:) = [0 0 0];

    for k = 1:numel(pathCompact)
        rNodes_ecef(1+k,:) = rSat_used_ecef(pathCompact(k),:);
        vNodes_ecef(1+k,:) = vSat_used_ecef(pathCompact(k),:);
    end

    rNodes_ecef(end,:) = rGS_end_ecef;
    vNodes_ecef(end,:) = [0 0 0];

    LLA_nodes = zeros(size(rNodes_ecef));
    for k = 1:size(rNodes_ecef,1)
        LLA_nodes(k,:) = ecef2lla_wgs84(rNodes_ecef(k,:));
    end

    [HopTable] = buildHopTable(HopNodes, LLA_nodes, rNodes_ecef, vNodes_ecef);

    % Export
    writeHopTableTxt(cfg.outTxt, tUse, cfg.inFile, cfg.maxDTE_km, cfg.maxISL_km, cfg.minElevation_deg, cfg.sampleTime_s, cfg.numberAttempts, HopTable);

    %% =========================
    %  6) PLOTS
    %  =========================
    if cfg.make3DScenarioViewer
        make3DScenarioViewerOnlyUsed(cfg, tUse, names, L1, L2, satTleIdx, usedSatIdx);
    end

    if cfg.make2DMapFigure
        make2DWorldMap(cfg, tUse, HopNodes, LLA_nodes);
    end

    %% =========================
    %  7) PACKAGE RESULT
    %  =========================
    result.solved = true;
    result.status = "Solved";
    result.tUse = tUse;
    result.HopTable = HopTable;
    result.usedSatIdx = usedSatIdx;
    result.usedSatNames = satNames_used;
    result.elapsed_s = toc(tStartTotal);

    if cfg.verbose
        fprintf("\n=== SOLUTION FOUND ===\n");
        fprintf("Time (UTC): %s\n", string(tUse));
        fprintf("Start DTE satellite: %s\n", satNames(startSatIdx));
        fprintf("End   DTE satellite: %s\n", satNames(endSatIdx));
        fprintf("Total hops: %d\n", height(HopTable));
        fprintf("Wrote hop table to %s\n", cfg.outTxt);
        fprintf("Total elapsed runtime: %.3f s\n", result.elapsed_s);
    end

catch ME
    result.solved = false;
    result.status = "ERROR: " + string(ME.message);
    result.elapsed_s = toc(tStartTotal);
    rethrow(ME);
end

end % main function


%% =========================
%  LOCAL HELPERS
%  =========================

function cfg = applyDefaults(cfg)
if ~isfield(cfg,"outTxt"), cfg.outTxt = "optical_link_hops.txt"; end
if ~isfield(cfg,"plotWindow_minutes"), cfg.plotWindow_minutes = 30; end
if ~isfield(cfg,"make3DScenarioViewer"), cfg.make3DScenarioViewer = true; end
if ~isfield(cfg,"make2DMapFigure"), cfg.make2DMapFigure = true; end
if ~isfield(cfg,"mapBasemap"), cfg.mapBasemap = "colorterrain"; end
if ~isfield(cfg,"verbose"), cfg.verbose = true; end
end

function [names, L1, L2] = parseTLEFile(inFile)
txt = fileread(inFile);
rawLines = splitlines(string(txt));
rawLines = rawLines(~cellfun(@(c) all(isspace(c)) || isempty(c), cellstr(rawLines)));

names = strings(0,1); L1 = strings(0,1); L2 = strings(0,1);
i = 1;
while i <= numel(rawLines)-2
    nameLine = rawLines(i);
    line1 = rawLines(i+1);
    line2 = rawLines(i+2);

    if startsWith(line1,"1 ") && startsWith(line2,"2 ")
        names(end+1,1) = strtrim(nameLine); %#ok<AGROW>
        L1(end+1,1)    = line1;             %#ok<AGROW>
        L2(end+1,1)    = line2;             %#ok<AGROW>
        i = i + 3;
    else
        i = i + 1;
    end
end
end

function [satCells, satTleIdx, loadWarnings] = loadSatellitesFromTLE(sc, names, L1, L2)
tmpFile = fullfile(tempdir, "one_sat_tmp.tle");
satCells = {};
satTleIdx = [];
loadWarnings = strings(0,1);

for k = 1:numel(names)
    fid = fopen(tmpFile, "w");
    fprintf(fid, "%s\n", names(k));
    fprintf(fid, "%s\n", L1(k));
    fprintf(fid, "%s\n", L2(k));
    fclose(fid);

    try
        satCells{end+1,1} = satellite(sc, tmpFile, "Name", char(names(k))); %#ok<AGROW>
        satTleIdx(end+1,1) = k; %#ok<AGROW>
    catch ME
        msg = sprintf("Skipping TLE block %d (%s): %s", k, names(k), ME.message);
        warning("%s", msg);
        loadWarnings(end+1,1) = string(msg); %#ok<AGROW>
    end
end
end

function [satNames, rSat_ecef, vSat_ecef, okMask] = computeSatStatesECEF(satCells, tUTC)
Ns = numel(satCells);
satNames = strings(Ns,1);
rSat_ecef = NaN(Ns,3);
vSat_ecef = NaN(Ns,3);
okMask = false(Ns,1);

for s = 1:Ns
    sat = satCells{s};
    satNames(s) = string(sat.Name);
    try
        [rECI_m, vECI_mps] = states(sat, tUTC);
        rECI_m   = rECI_m(:);
        vECI_mps = vECI_mps(:);

        [rEcef, vEcef] = eci2ecef_posvel_simple(rECI_m, vECI_mps, tUTC);
        rSat_ecef(s,:) = rEcef(:).';
        vSat_ecef(s,:) = vEcef(:).';
        okMask(s) = true;
    catch
    end
end
end

function [bestIdx, info] = pickNearestDTE(rGS_ecef, gsLLA, rSat_ecef, okMask, maxDTE_m, minEl_deg)
Ns = size(rSat_ecef,1);
bestIdx = NaN;
bestDist = inf;

info = struct("dist_m",NaN,"el_deg",NaN);

for s = 1:Ns
    if ~okMask(s), continue; end

    rs = rSat_ecef(s,:);
    d  = norm(rs - rGS_ecef);
    if d > maxDTE_m, continue; end

    el = elevationFromECEF(gsLLA, rGS_ecef, rs);
    if el < minEl_deg, continue; end

    if d < bestDist
        bestDist = d;
        bestIdx = s;
        info.dist_m = d;
        info.el_deg = el;
    end
end
end

function pathIdx = shortestPathISL(rSat_ecef, okMask, startIdx, endIdx, maxISL_m, Re_m)
if ~okMask(startIdx) || ~okMask(endIdx)
    pathIdx = [];
    return;
end

I = []; J = []; W = [];
validIdx = find(okMask);
Nv = numel(validIdx);

for ii = 1:Nv
    a = validIdx(ii);
    ra = rSat_ecef(a,:);
    for jj = (ii+1):Nv
        b = validIdx(jj);
        rb = rSat_ecef(b,:);
        d = norm(rb - ra);
        if d <= maxISL_m && hasLOS_sphere(ra, rb, Re_m)
            I(end+1,1) = a; %#ok<AGROW>
            J(end+1,1) = b; %#ok<AGROW>
            W(end+1,1) = d; %#ok<AGROW>
            I(end+1,1) = b; %#ok<AGROW>
            J(end+1,1) = a; %#ok<AGROW>
            W(end+1,1) = d; %#ok<AGROW>
        end
    end
end

if isempty(W)
    pathIdx = [];
    return;
end

G = graph(I, J, W);
[pathIdx, ~] = shortestpath(G, startIdx, endIdx, "Method","positive");
end

function HopTable = buildHopTable(HopNodes, LLA_nodes, rNodes_ecef, vNodes_ecef)
lat = LLA_nodes(:,1); lon = LLA_nodes(:,2); alt = LLA_nodes(:,3);

nHops = numel(HopNodes) - 1;
HopNum  = (1:nHops).';
From    = strings(nHops,1);
To      = strings(nHops,1);
Dist_km = zeros(nHops,1);
RelV_radial_mps = zeros(nHops,1);
RelAlt_m = zeros(nHops,1);

for h = 1:nHops
    From(h) = HopNodes(h);
    To(h)   = HopNodes(h+1);

    ra = rNodes_ecef(h,:);    va = vNodes_ecef(h,:);
    rb = rNodes_ecef(h+1,:);  vb = vNodes_ecef(h+1,:);

    dr = (rb - ra);
    d  = norm(dr);
    Dist_km(h) = d/1e3;

    if d > 0
        rhat = dr ./ d;         % LOS unit vector (a->b)
        vrel = (vb - va);       % relative velocity of b wrt a
        RelV_radial_mps(h) = dot(vrel, rhat);  % +separating, -closing
    else
        RelV_radial_mps(h) = 0;
    end

    RelAlt_m(h) = alt(h+1) - alt(h);
end

HopTable = table( ...
    HopNum, From, To, Dist_km, RelV_radial_mps, RelAlt_m, ...
    lat(1:end-1), lon(1:end-1), alt(1:end-1), ...
    lat(2:end),   lon(2:end),   alt(2:end), ...
    'VariableNames', { ...
      'Hop','From','To','Distance_km','RelVelRadial_mps','RelAlt_m', ...
      'From_lat_deg','From_lon_deg','From_alt_m', ...
      'To_lat_deg','To_lon_deg','To_alt_m'} );
end

function make3DScenarioViewerOnlyUsed(cfg, tUse, names, L1, L2, satTleIdx, usedSatIdx)
tPlotStart = tUse;
tPlotStop  = tUse + minutes(cfg.plotWindow_minutes);

scPlot = satelliteScenario(tPlotStart, tPlotStop, max(1, min(cfg.sampleTime_s,30)));

groundStation(scPlot, cfg.startLLA(1), cfg.startLLA(2), "Name","GS_START");
groundStation(scPlot, cfg.endLLA(1),   cfg.endLLA(2),   "Name","GS_END");

Nu = numel(usedSatIdx);
for k = 1:Nu
    origIdx = usedSatIdx(k);
    tleIdx  = satTleIdx(origIdx);
    addSatelliteFromTLELines(scPlot, names(tleIdx), L1(tleIdx), L2(tleIdx));
end

satelliteScenarioViewer(scPlot, "Dimension","3D");
end

function make2DWorldMap(cfg, tUse, HopNodes, LLA_nodes)
lat = LLA_nodes(:,1);
lon = LLA_nodes(:,2);

figure("Name","Optical Relay Path (2D Basemap)","Color","w");
gx = geoaxes;
geobasemap(gx, cfg.mapBasemap);
hold(gx,"on");

[latPlot, lonPlot] = splitDatelinePolyline(lat, lon);
geoplot(gx, latPlot, lonPlot, "-r", "LineWidth", 2);
geoscatter(gx, lat, lon, 40, "r", "filled");

for k = 1:numel(HopNodes)
    text(gx, lat(k), lon(k), "  " + string(HopNodes(k)), ...
        "FontSize", 9, "Color","w", "Interpreter","none");
end

title(gx, sprintf("Optical Relay Path @ %s UTC", string(tUse)), "Interpreter","none");
hold(gx,"off");
end

function el_deg = elevationFromECEF(gsLLA, rGS_ecef, rSat_ecef)
lat = deg2rad(gsLLA(1));
lon = deg2rad(gsLLA(2));

R = [ -sin(lon)            cos(lon)            0;
      -sin(lat)*cos(lon)  -sin(lat)*sin(lon)   cos(lat);
       cos(lat)*cos(lon)   cos(lat)*sin(lon)   sin(lat) ];

rho = (rSat_ecef(:) - rGS_ecef(:));
enu = R * rho;

E = enu(1); N = enu(2); U = enu(3);
el_deg = rad2deg(atan2(U, hypot(E,N)));
end

function tf = hasLOS_sphere(r1, r2, Re_m)
r1 = r1(:); r2 = r2(:);
u  = r2 - r1;
t  = -dot(r1,u) / dot(u,u);
t  = max(0, min(1, t));
closest = r1 + t*u;
tf = (norm(closest) > Re_m);
end

function r_ecef = lla2ecef_wgs84(lla)
lat = deg2rad(lla(1)); lon = deg2rad(lla(2)); h = lla(3);
a = 6378137.0; f = 1/298.257223563; e2 = f*(2-f);
N = a / sqrt(1 - e2*sin(lat)^2);
x = (N + h)*cos(lat)*cos(lon);
y = (N + h)*cos(lat)*sin(lon);
z = (N*(1-e2) + h)*sin(lat);
r_ecef = [x y z];
end

function lla = ecef2lla_wgs84(r)
x=r(1); y=r(2); z=r(3);
a = 6378137.0; f = 1/298.257223563; e2 = f*(2-f);
lon = atan2(y,x);
p = hypot(x,y);
lat = atan2(z, p*(1-e2));
for k=1:6
    N = a / sqrt(1 - e2*sin(lat)^2);
    h = p/cos(lat) - N;
    lat = atan2(z, p*(1 - e2*(N/(N+h))));
end
N = a / sqrt(1 - e2*sin(lat)^2);
h = p/cos(lat) - N;
lla = [rad2deg(lat), rad2deg(lon), h];
end

function [r_ecef, v_ecef] = eci2ecef_posvel_simple(r_eci, v_eci, tUTC)
gmst = gmstRadians(tUTC);
R3 = [ cos(gmst)  sin(gmst) 0;
      -sin(gmst)  cos(gmst) 0;
       0          0         1];

r_ecef = R3 * r_eci(:);
v_rot  = R3 * v_eci(:);

omega = [0; 0; 7.2921150e-5];
v_ecef = v_rot - cross(omega, r_ecef);
end

function gmst = gmstRadians(tUTC)
jd = juliandate(tUTC);
T = (jd - 2451545.0)/36525.0;
gmst_sec = 67310.54841 + (876600*3600 + 8640184.812866)*T + 0.093104*T^2 - 6.2e-6*T^3;
gmst = deg2rad(mod(gmst_sec/240, 360));
end

function satObj = addSatelliteFromTLELines(sc, nameLine, line1, line2)
tmpFile = fullfile(tempdir, sprintf("tle_%s.tle", char(java.util.UUID.randomUUID)));
fid = fopen(tmpFile, "w");
fprintf(fid, "%s\n", strtrim(string(nameLine)));
fprintf(fid, "%s\n", string(line1));
fprintf(fid, "%s\n", string(line2));
fclose(fid);

satObj = satellite(sc, tmpFile, "Name", char(strtrim(string(nameLine))));
end

function writeHopTableTxt(outTxt, tUse, inFile, maxDTE_km, maxISL_km, minEl_deg, sampleTime_s, numberAttempts, HopTable)
fid = fopen(outTxt, "w");
fprintf(fid, "Optical link hops (snapshot)\n");
fprintf(fid, "Time (UTC): %s\n", string(tUse));
fprintf(fid, "TLE file: %s\n", string(inFile));
fprintf(fid, "Constraints: maxDTE_km=%.1f, maxISL_km=%.1f, minElevation_deg=%.1f\n", maxDTE_km, maxISL_km, minEl_deg);
fprintf(fid, "Auto-time: sampleTime_s=%.0f, numberAttempts=%d\n", sampleTime_s, numberAttempts);
fprintf(fid, "\n");

for h = 1:height(HopTable)
    fprintf(fid, "Hop %d: %s -> %s | %.3f km | RelV(radial) %.3f m/s | RelAlt %.1f m\n", ...
        HopTable.Hop(h), HopTable.From(h), HopTable.To(h), HopTable.Distance_km(h), ...
        HopTable.RelVelRadial_mps(h), HopTable.RelAlt_m(h));
end

fprintf(fid, "\n--- TSV TABLE ---\n");
fclose(fid);

writetable(HopTable, outTxt, "Delimiter","\t", "WriteMode","append");
end
function [latOut, lonOut] = splitDatelinePolyline(latIn, lonIn)
% Splits a lat/lon polyline at the dateline so it doesn't draw across the whole globe.
% - Inputs: latIn, lonIn in degrees (vectors)
% - Outputs: latOut, lonOut with inserted points at +/-180 and NaNs to break segments.

latIn = latIn(:);
lonIn = wrapTo180(lonIn(:));   % keep in [-180,180]

latOut = latIn(1);
lonOut = lonIn(1);

for k = 2:numel(latIn)
    lat1 = latIn(k-1); lon1 = lonIn(k-1);
    lat2 = latIn(k);   lon2 = lonIn(k);

    dlon = lon2 - lon1;

    % If we jump more than 180 deg in lon, we crossed the dateline
    if abs(dlon) > 180
        % Choose which dateline we hit (+180 or -180) based on direction
        if lon1 > 0 && lon2 < 0
            % Example: 170 -> -170, treat lon2 as 190 and cross +180
            lon2_adj = lon2 + 360;
            lonCross = 180;
            t = (lonCross - lon1) / (lon2_adj - lon1);
        elseif lon1 < 0 && lon2 > 0
            % Example: -170 -> 170, treat lon2 as -190 and cross -180
            lon2_adj = lon2 - 360;
            lonCross = -180;
            t = (lonCross - lon1) / (lon2_adj - lon1);
        else
            % Rare edge case; just break line
            latOut(end+1,1) = NaN; %#ok<AGROW>
            lonOut(end+1,1) = NaN; %#ok<AGROW>
            latOut(end+1,1) = lat2; %#ok<AGROW>
            lonOut(end+1,1) = lon2; %#ok<AGROW>
            continue;
        end

        % Linear interpolation for a nice-looking split point
        t = max(0, min(1, t));
        latCross = lat1 + t*(lat2 - lat1);

        % Add point at dateline, break, then continue from opposite dateline
        latOut(end+1,1) = latCross;   lonOut(end+1,1) = lonCross; %#ok<AGROW>
        latOut(end+1,1) = NaN;        lonOut(end+1,1) = NaN;      %#ok<AGROW>
        latOut(end+1,1) = latCross;   lonOut(end+1,1) = -lonCross; %#ok<AGROW>
        latOut(end+1,1) = lat2;       lonOut(end+1,1) = lon2;     %#ok<AGROW>
    else
        % Normal segment
        latOut(end+1,1) = lat2; %#ok<AGROW>
        lonOut(end+1,1) = lon2; %#ok<AGROW>
    end
end
end
