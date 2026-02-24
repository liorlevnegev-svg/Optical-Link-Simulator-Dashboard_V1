function RUN_MasterLinkDashboard_v1()
%RUN_MasterLinkDashboard  GUI dashboard for optical relay path + link budget
%
% Layout:
%   Top-Left:    User parameters + Advanced Settings button + Run
%   Bottom-Left: TLE text (Left) | Readouts (Middle) | Hop Table (Right)
%   Top-Right:   2D world map (geoaxes) with red hop line
%   Bottom-Right:3D globe (uiaxes) with used satellites + GS

    % -------------------------
    % App state (defaults)
    % -------------------------
    S = struct();

    % Defaults inputs
    S.requestList = ["Amazon Leo"];   % default selected items (string array)
    
    % Satellite Items available for selection
    satItems = { ...
    'Kepler AETHER'
    'SDA'
    'Tranche 0'
    'Tranche 1'
    'Amazon Leo'
    'Starlink (all)'
    '6'
    '7'
    '8'
    '9'
    '10'
    '11'
    '12'
    '13'
    '15'
    '17'
    'ESA SpaceDataHighwayNetwork'
    'EUTELSAT 9B'
    'EDRS-C' };

    S.excelPath           = "Optical Constellation Catalogue_Lior Lev.xlsx";
    S.expireDays          = 14;

    S.citiesXlsx = "CatalogueOfCities.xlsx";   
    S.startCity  = "Custom";                  
    S.endCity    = "Custom";

    S.startLLA            = [40.410000, -3.700000, 657.00];  % [lat lon alt_m] Madrid
    S.endLLA              = [43.650000, -79.390000, 76.00];  % Tokyo
    S.useNow              = true;
    S.customTimeText      = "YYYY-MM-DD HH:MM:SS";    % UTC text

    S.maxDTE_km           = 2000;
    S.maxISL_km           = 2000;
    S.minElevation_deg    = 20;

    S.atpTime_ms          = 50;       % ATP time between hops in milliseconds
    S.openSolverGlobe     = true;      
    S.darkMode            = true;

    % Advanced settings
    S.sampleTime_ms       = 3600000;   % 1 hour in ms
    S.numberAttempts      = 10;
    S.mapBasemap          = "satellite";

    % Optical constants
    S.C = defaultOpticalConstants();

    % Solver figure flags
    S.makeSolver2DFigure  = false;

    % Runtime artifacts
    S.outTLEFile   = "";
    S.hopsFile     = "optical_link_hops.txt";
    S.result       = [];
    S.T_link       = table();

    % ---- Load cities catalogue (for start/end dropdowns) ----
    try
        [cities, cityNames] = loadCitiesCatalogue(S.citiesXlsx);
        % Always include a Custom option at top
        cityNames = ["Custom"; cityNames(:)];
    catch
        warning("Could not load cities catalogue. Using Custom only.");
        cities = table();
        cityNames = ["Custom"];
    end

    % -------------------------
    % Build UI
    % -------------------------
    fig = uifigure("Name","Optical Links — Master Dashboard", ...
                   "Position",[50 50 1500 900]);

    % Main grid: 2x2. Adjusted to give left side more space, shifting globes right.
    gl = uigridlayout(fig,[2 2]);
    gl.RowHeight = {'0.52x','0.48x'};
    gl.ColumnWidth = {'0.63x','0.37x'}; 
    gl.Padding = [8 8 8 8];
    gl.RowSpacing = 8;
    gl.ColumnSpacing = 8;

    % Panels
    pTL = uipanel(gl,"Title","Inputs","FontWeight","bold");
    pTL.Layout.Row = 1; pTL.Layout.Column = 1;

    pBL = uipanel(gl,"Title","Data & Link Parameters","FontWeight","bold");
    pBL.Layout.Row = 2; pBL.Layout.Column = 1;

    pTR = uipanel(gl,"Title","2D World Map","FontWeight","bold");
    pTR.Layout.Row = 1; pTR.Layout.Column = 2;

    pBR = uipanel(gl,"Title","3D Globe","FontWeight","bold");
    pBR.Layout.Row = 2; pBR.Layout.Column = 2;

    % -------- Top-Left: Inputs grid --------
    gTL = uigridlayout(pTL,[11 4]);
    gTL.RowHeight   = {22, 90,22,22,22,22,22,22,22,28,'1x'}; 
    gTL.ColumnWidth = {150,'1x',130,'1x'};
    gTL.Padding     = [8 8 8 8];
    gTL.RowSpacing  = 6;
    gTL.ColumnSpacing = 8;

    % Row 1: User Manual Button
    btnManual = uibutton(gTL,"Text","User Manual", ...
        "ButtonPushedFcn", @(src,evt) safeCall(@() onOpenManual()));
    btnManual.Layout.Row = 1; btnManual.Layout.Column = 1;

    % Row 2: Satellite Sets (Multi-select Listbox)
    lbl = uilabel(gTL,"Text","Satellite sets:","HorizontalAlignment","right", ...
        "Tooltip","Select one or more. Hold Ctrl/Cmd to select multiple.");
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    
    lbRequest = uilistbox(gTL, ...
        "Items", satItems, ...
        "Multiselect","on"); 
    lbRequest.Layout.Row = 2;
    lbRequest.Layout.Column = [2 4];
    
    % Set default selections
    defSel = intersect(string(satItems), string(S.requestList), "stable");
    if isempty(defSel), defSel = "Tranche 0"; end
    lbRequest.Value = cellstr(defSel);

    % Row 3: Start city dropdown + coords box
    lbl = uilabel(gTL,"Text","Start city:","HorizontalAlignment","right");
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    
    ddStartCity = uidropdown(gTL,"Items",cellstr(cityNames), "Value","Madrid");
    ddStartCity.Layout.Row = 3; ddStartCity.Layout.Column = 2;
    
    edStart = uieditfield(gTL,"text","Value",llaToText(S.startLLA));
    edStart.Layout.Row = 3; edStart.Layout.Column = [3 4];
    
    % Row 4: End city dropdown + coords box
    lbl = uilabel(gTL,"Text","End city:","HorizontalAlignment","right");
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    
    ddEndCity = uidropdown(gTL,"Items",cellstr(cityNames), "Value","Toronto");
    ddEndCity.Layout.Row = 4; ddEndCity.Layout.Column = 2;
    
    edEnd = uieditfield(gTL,"text","Value",llaToText(S.endLLA));
    edEnd.Layout.Row = 4; edEnd.Layout.Column = [3 4];
    
    ddStartCity.ValueChangedFcn = @(src,evt) onCityPicked(src.Value, edStart, "start");
    ddEndCity.ValueChangedFcn   = @(src,evt) onCityPicked(src.Value, edEnd, "end");
    
    edStart.ValueChangedFcn = @(src,evt) onCoordsEdited(src.Value, ddStartCity);
    edEnd.ValueChangedFcn   = @(src,evt) onCoordsEdited(src.Value, ddEndCity);

    % Row 5: Time controls
    cbNow = uicheckbox(gTL,"Text","NOW (UTC)","Value",S.useNow);
    cbNow.Layout.Row = 5; cbNow.Layout.Column = 2;

    lbl = uilabel(gTL,"Text","Or time (UTC):","HorizontalAlignment","right");
    lbl.Layout.Row = 5; lbl.Layout.Column = 3;

    edTime = uieditfield(gTL,"text","Value",char(S.customTimeText));
    edTime.Layout.Row = 5; edTime.Layout.Column = 4;

    % Row 6: Distances
    lbl = uilabel(gTL,"Text","Max GS link distance (km):","HorizontalAlignment","right");
    lbl.Layout.Row = 6; lbl.Layout.Column = 1;

    edMaxDTE = uieditfield(gTL,"numeric","Value",S.maxDTE_km);
    edMaxDTE.Layout.Row = 6; edMaxDTE.Layout.Column = 2;

    lbl = uilabel(gTL,"Text","Max ISL distance (km):","HorizontalAlignment","right");
    lbl.Layout.Row = 6; lbl.Layout.Column = 3;

    edMaxISL = uieditfield(gTL,"numeric","Value",S.maxISL_km);
    edMaxISL.Layout.Row = 6; edMaxISL.Layout.Column = 4;

    % Row 7: Min elevation + ATP time
    lbl = uilabel(gTL,"Text","Min GS elevation angle (deg):","HorizontalAlignment","right");
    lbl.Layout.Row = 7; lbl.Layout.Column = 1;

    edMinEl = uieditfield(gTL,"numeric","Value",S.minElevation_deg);
    edMinEl.Layout.Row = 7; edMinEl.Layout.Column = 2;

    lbl = uilabel(gTL,"Text","ATP time per hop (ms):","HorizontalAlignment","right");
    lbl.Layout.Row = 7; lbl.Layout.Column = 3;

    edATP = uieditfield(gTL,"numeric","Value",S.atpTime_ms);
    edATP.Layout.Row = 7; edATP.Layout.Column = 4;

    % Row 8: Open solver globe viewer
    cbOpenGlobe = uicheckbox(gTL,"Text","Open solver globe viewer","Value",S.openSolverGlobe);
    cbOpenGlobe.Layout.Row = 8; cbOpenGlobe.Layout.Column = [2 4];

    % Row 9: Buttons
    btnAdvanced = uibutton(gTL,"Text","Advanced settings...", ...
        "ButtonPushedFcn", @(src,evt) safeCall(@() onAdvanced(src,evt)));
    btnAdvanced.Layout.Row = 9; btnAdvanced.Layout.Column = [1 2];

    btnRun = uibutton(gTL,"Text","Run simulation","FontWeight","bold", ...
        "ButtonPushedFcn", @(src,evt) safeCall(@() onRun(src,evt)));
    btnRun.Layout.Row = 9; btnRun.Layout.Column = [3 4];

    % Row 10: Status
    lblStatus = uilabel(gTL,"Text","Status: Idle","FontWeight","bold");
    lblStatus.Layout.Row = 10; lblStatus.Layout.Column = [1 4];

    % Row 11: Log
    txtLog = uitextarea(gTL,"Editable","off");
    txtLog.Layout.Row = 11; txtLog.Layout.Column = [1 4];
    txtLog.Value = string("Log:"); 

    % -------- Bottom-Left: TLE + Stats + Table --------
    % Split into 3 columns: Narrow TLE, Fixed Middle Stats, Expanding Right Table
    
    gBL = uigridlayout('Parent', pBL, 'RowHeight', {'1x'}, 'ColumnWidth', {270, 250, '1x'});
    gBL.Padding = [6 6 6 6];
    gBL.ColumnSpacing = 8;

    % 1. TLE viewer (Left - narrow)
    pTLE = uipanel(gBL,"Title","TLE file used","FontWeight","bold");
    pTLE.Layout.Row = 1; pTLE.Layout.Column = 1;

    gTLE = uigridlayout(pTLE,[1 1]);
    gTLE.Padding = [4 4 4 4];
    tleArea = uitextarea(gTLE,"Editable","off","FontName","Consolas");
    tleArea.Layout.Row = 1; tleArea.Layout.Column = 1;
    tleArea.Value = string("(Run to load TLE text)"); 

    % 2. Summary Readouts (Middle - separating TLE and Table)
    pStats = uipanel(gBL,"Title","Link Summary","FontWeight","bold");
    pStats.Layout.Row = 1; pStats.Layout.Column = 2;

    gStats = uigridlayout(pStats,[11 1]);
    gStats.Padding = [8 8 8 8];
    gStats.RowHeight = {26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26};

    row1 = uigridlayout(gStats,[1 2]);
    row1.Layout.Row = 1; row1.ColumnWidth = {100,'1x'}; row1.Padding = [0 0 0 0];
    uilabel(row1,"Text","Elapsed sim time:","HorizontalAlignment","left");
    edElapsed = uieditfield(row1,"text","Editable","off","Value","—");

    row2 = uigridlayout(gStats,[1 2]);
    row2.Layout.Row = 2; row2.ColumnWidth = {100,'1x'}; row2.Padding = [0 0 0 0];
    uilabel(row2,"Text","Available Sats:","HorizontalAlignment","left");
    edAvailSats = uieditfield(row2,"text","Editable","off","Value","—");

    row3 = uigridlayout(gStats,[1 2]);
    row3.Layout.Row = 3; row3.ColumnWidth = {100,'1x'}; row3.Padding = [0 0 0 0];
    uilabel(row3,"Text","Used Satellites:","HorizontalAlignment","left");
    edUsedSats = uieditfield(row3,"text","Editable","off","Value","—");

    row4 = uigridlayout(gStats,[1 2]);
    row4.Layout.Row = 4; row4.ColumnWidth = {100,'1x'}; row4.Padding = [0 0 0 0];
    uilabel(row4,"Text","Total distance:","HorizontalAlignment","left");
    edTotalDist = uieditfield(row4,"text","Editable","off","Value","—");

    row5 = uigridlayout(gStats,[1 2]);
    row5.Layout.Row = 5; row5.ColumnWidth = {100,'1x'}; row5.Padding = [0 0 0 0];
    uilabel(row5,"Text","Total link time:","HorizontalAlignment","left");
    edTotalLink = uieditfield(row5,"text","Editable","off","Value","—");

    row6 = uigridlayout(gStats,[1 2]);
    row6.Layout.Row = 6; row6.ColumnWidth = {100,'1x'}; row6.Padding = [0 0 0 0];
    uilabel(row6,"Text","Start GS Elev:","HorizontalAlignment","left");
    edStartEl = uieditfield(row6,"text","Editable","off","Value","—");

    row7 = uigridlayout(gStats,[1 2]);
    row7.Layout.Row = 7; row7.ColumnWidth = {100,'1x'}; row7.Padding = [0 0 0 0];
    uilabel(row7,"Text","End GS Elev:","HorizontalAlignment","left");
    edEndEl = uieditfield(row7,"text","Editable","off","Value","—");

    row8 = uigridlayout(gStats,[1 2]);
    row8.Layout.Row = 8; row8.ColumnWidth = {100,'1x'}; row8.Padding = [0 0 0 0];
    uilabel(row8,"Text","Transmit Power:","HorizontalAlignment","left");
    edTxPower = uieditfield(row8,"text","Editable","off","Value","—");

    row9 = uigridlayout(gStats,[1 2]);
    row9.Layout.Row = 9; row9.ColumnWidth = {100,'1x'}; row9.Padding = [0 0 0 0];
    uilabel(row9,"Text","ATP Time / hop:","HorizontalAlignment","left");
    edATPDisplay = uieditfield(row9,"text","Editable","off","Value","—");

    row10 = uigridlayout(gStats,[1 2]);
    row10.Layout.Row = 10; row10.ColumnWidth = {100,'1x'}; row10.Padding = [0 0 0 0];
    uilabel(row10,"Text","Start Time (UTC):","HorizontalAlignment","left");
    edStartTime = uieditfield(row10,"text","Editable","off","Value","—");

    row11 = uigridlayout(gStats,[1 2]);
    row11.Layout.Row = 11; row11.ColumnWidth = {80,'1x'}; row11.Padding = [0 0 0 0];
    uilabel(row11,"Text","End Time (UTC):","HorizontalAlignment","left");
    edEndTime = uieditfield(row11,"text","Editable","off","Value","—");

    % 3. Hop Table (Right - vertical window)
    pTab = uipanel(gBL,"Title","Hop Sequence Data","FontWeight","bold");
    pTab.Layout.Row = 1; pTab.Layout.Column = 3;

    gTab = uigridlayout(pTab,[1 1]);
    gTab.Padding = [4 4 4 4];

    hopTable = uitable(gTab);
    hopTable.Layout.Row = 1; hopTable.Layout.Column = 1;
    hopTable.Data = table();
    hopTable.ColumnSortable = false; 
    hopTable.RowStriping = "on";

    % -------- Top-Right: 2D map --------
    gTR = uigridlayout(pTR,[1 1]);
    gTR.Padding = [8 8 8 8];

    gx = geoaxes(gTR);
    try
        geobasemap(gx, S.mapBasemap);
    catch
        geobasemap(gx, 'grayterrain');
    end

    % -------- Bottom-Right: 3D globe --------
    gBR = uigridlayout(pBR,[1 1]);
    gBR.Padding = [8 8 8 8];

    ax3 = uiaxes(gBR);
    ax3.XGrid = "on"; ax3.YGrid = "on"; ax3.ZGrid = "on";
    axis(ax3,"equal");
    view(ax3,3);
    rotate3d(ax3,"on");
    title(ax3,"(Run to render globe)");

    renderEmptyGlobe(ax3);

    % -------- Dark mode styling --------
    if isfield(S,"darkMode") && S.darkMode
        applyDarkMode(fig);
    end

    % -------------------------
    % Safe callback wrapper
    % -------------------------
    function safeCall(fcn)
        try
            if ~isvalid(fig)
                return;
            end
            fcn();
        catch ME
            disp(getReport(ME,'extended','hyperlinks','off'));
            if isvalid(fig)
                try
                    uialert(fig, string(ME.message), "Callback error");
                catch
                end
            end
        end
    end

    % -------------------------
    % Callbacks
    % -------------------------
    function onOpenManual()
        manualPath = "User Manual_OLSD.pdf";
        if isfile(manualPath)
            try
                open(manualPath);
            catch ME
                uialert(fig, "Could not open manual: " + ME.message, "Error");
            end
        else
            uialert(fig, "Notice: " + manualPath + " not found in the current directory.", "File Not Found");
        end
    end

    function onCityPicked(cityName, coordEdit, whichOne)
        cityName = string(cityName);
        if cityName == "Custom"
            return;
        end
        if isempty(cities)
            return; 
        end
    
        idx = find(string(cities.City) == cityName, 1, "first");
        if isempty(idx)
            appendLog("City not found in catalogue: " + cityName);
            return;
        end
    
        lla = [cities.Lat_deg(idx), cities.Lon_deg(idx), cities.Alt_m(idx)];
        coordEdit.Value = llaToText(lla);
    
        if whichOne == "start"
            S.startCity = cityName;
            S.startLLA  = lla;
        else
            S.endCity = cityName;
            S.endLLA  = lla;
        end
    end
    
    function onCoordsEdited(~, cityDropdown)
        if string(cityDropdown.Value) ~= "Custom"
            cityDropdown.Value = "Custom";
        end
    end

    function onAdvanced(~,~)
        adv = uifigure("Name","Advanced settings", ...
            "Position",[200 200 800 650], ...
            "WindowStyle","modal");

        gA = uigridlayout(adv,[16 4]);
        gA.Padding = [10 10 10 10];
        gA.RowHeight = repmat({24},1,15);
        gA.RowHeight{16} = '1x';
        gA.ColumnWidth = {200,'1x',200,'1x'};
        gA.RowSpacing = 8;
        gA.ColumnSpacing = 10;

        lbl = uilabel(gA,"Text","Excel catalogue path:","HorizontalAlignment","right");
        lbl.Layout.Row = 1; lbl.Layout.Column = 1;
        edExcel = uieditfield(gA,"text","Value",char(S.excelPath));
        edExcel.Layout.Row = 1; edExcel.Layout.Column = [2 4];

        lbl = uilabel(gA,"Text","Use existing TLE if newer than (days):","HorizontalAlignment","right");
        lbl.Layout.Row = 2; lbl.Layout.Column = 1;
        edExpire = uieditfield(gA,"numeric","Value",S.expireDays);
        edExpire.Layout.Row = 2; edExpire.Layout.Column = 2;

        lbl = uilabel(gA,"Text","Sample time (ms):","HorizontalAlignment","right");
        lbl.Layout.Row = 3; lbl.Layout.Column = 1;
        edSample = uieditfield(gA,"numeric","Value",S.sampleTime_ms);
        edSample.Layout.Row = 3; edSample.Layout.Column = 2;

        lbl = uilabel(gA,"Text","Max attempts:","HorizontalAlignment","right");
        lbl.Layout.Row = 3; lbl.Layout.Column = 3;
        edAttempts = uieditfield(gA,"numeric","Value",S.numberAttempts);
        edAttempts.Layout.Row = 3; edAttempts.Layout.Column = 4;

        lbl = uilabel(gA,"Text","Map basemap:","HorizontalAlignment","right");
        lbl.Layout.Row = 4; lbl.Layout.Column = 1;
        ddBasemap = uidropdown(gA, ...
            "Items",{'satellite','colorterrain','grayterrain','topographic','streets','streets-light','streets-dark','landcover','bluegreen','grayland','darkwater','none'}, ...
            "Value",char(S.mapBasemap));
        ddBasemap.Layout.Row = 4; ddBasemap.Layout.Column = 2;

        function addCField(row, labelText, initVal, setterFcn, cLabel, cEdit)
            lbl2 = uilabel(gA,"Text",labelText,"HorizontalAlignment","right");
            lbl2.Layout.Row = row; lbl2.Layout.Column = cLabel;
            ed = uieditfield(gA,"numeric","Value",initVal);
            ed.Layout.Row = row; ed.Layout.Column = cEdit;
            ed.ValueChangedFcn = @(src,~) setterFcn(src.Value);
        end

        function setC(name, val)
            S.C.(name) = val;
        end

        % Optical constants mapped exactly to
        % FXN_compute_optical_hop_table_v1
        addCField(5,"Wavelength (nm):",       S.C.lambda_nm,        @(v)setC("lambda_nm",v), 1, 2);
        addCField(5,"Data rate (Gbps):",      S.C.dataRate_bps/1e9, @(v)setC("dataRate_bps",v*1e9), 3, 4);

        addCField(6,"Pt GS (W):",             S.C.Pt_gs_W,          @(v)setC("Pt_gs_W",v), 1, 2);
        addCField(6,"Pt LCT (W):",            S.C.Pt_lct_W,         @(v)setC("Pt_lct_W",v), 3, 4);

        addCField(7,"D_tx GS (mm):",          S.C.D_tx_gs_mm,       @(v)setC("D_tx_gs_mm",v), 1, 2);
        addCField(7,"D_rx GS (mm):",          S.C.D_rx_gs_mm,       @(v)setC("D_rx_gs_mm",v), 3, 4);

        addCField(8,"D_tx LCT (mm):",         S.C.D_tx_lct_mm,      @(v)setC("D_tx_lct_mm",v), 1, 2);
        addCField(8,"D_rx LCT (mm):",         S.C.D_rx_lct_mm,      @(v)setC("D_rx_lct_mm",v), 3, 4);

        addCField(9,"Divergence GS (urad):",  S.C.theta_div_gs_urad,  @(v)setC("theta_div_gs_urad",v), 1, 2);
        addCField(9,"Divergence LCT (urad):", S.C.theta_div_lct_urad, @(v)setC("theta_div_lct_urad",v), 3, 4);

        addCField(10,"Pointing err TX (urad):",S.C.theta_err_tx_urad, @(v)setC("theta_err_tx_urad",v), 1, 2);
        addCField(10,"Pointing err RX (urad):",S.C.theta_err_rx_urad, @(v)setC("theta_err_rx_urad",v), 3, 4);

        addCField(11,"Eta TX GS (%):",        S.C.eta_tx_gs_pct,    @(v)setC("eta_tx_gs_pct",v), 1, 2);
        addCField(11,"Eta RX GS (%):",        S.C.eta_rx_gs_pct,    @(v)setC("eta_rx_gs_pct",v), 3, 4);

        addCField(12,"Eta TX LCT (%):",       S.C.eta_tx_lct_pct,   @(v)setC("eta_tx_lct_pct",v), 1, 2);
        addCField(12,"Eta RX LCT (%):",       S.C.eta_rx_lct_pct,   @(v)setC("eta_rx_lct_pct",v), 3, 4);

        addCField(13,"Bits per symbol:",      S.C.bits_per_symbol,  @(v)setC("bits_per_symbol",v), 1, 2);
        addCField(13,"Packet bits:",          S.C.packetBits,       @(v)setC("packetBits",v), 3, 4);

        addCField(14,"Preq (dBm):",           S.C.Preq_dBm,         @(v)setC("Preq_dBm",v), 1, 2);
        addCField(14,"Tropo Height (km):",    S.C.h_tropo_km,       @(v)setC("h_tropo_km",v), 3, 4);

        addCField(15,"Atm. Att. Coef (km^-1):",S.C.atm_att_coef,    @(v)setC("atm_att_coef",v), 1, 2);

        % Buttons
        btnSave = uibutton(gA,"Text","Save","FontWeight","bold", ...
            "ButtonPushedFcn", @(~,~) onSaveAndClose());
        btnSave.Layout.Row = 16; btnSave.Layout.Column = 3;

        btnCancel = uibutton(gA,"Text","Cancel", ...
            "ButtonPushedFcn", @(~,~) close(adv));
        btnCancel.Layout.Row = 16; btnCancel.Layout.Column = 4;

        if isfield(S,"darkMode") && S.darkMode
            applyDarkMode(adv);
        end

        function onSaveAndClose()
            S.excelPath       = string(edExcel.Value);
            S.expireDays      = edExpire.Value;
            S.sampleTime_ms   = edSample.Value;
            S.numberAttempts  = edAttempts.Value;
            S.mapBasemap      = string(ddBasemap.Value);
            close(adv);
        end
    end

    function onRun(~,~)
        tStart = tic;
        if ~isvalid(fig), return; end

        % a) Make sure the Satellite Scenario Viewer is closed
        try
            figHandles = findall(0, 'Type', 'figure');
            for f = 1:numel(figHandles)
                if contains(figHandles(f).Name, 'Satellite Scenario', 'IgnoreCase', true)
                    close(figHandles(f));
                end
            end
        catch
        end

        % b) Clear the log for each rerun
        txtLog.Value = string("Log:");
        drawnow;

        try
            setStatus("Running...", true);
            edElapsed.Value = "Running...";
            edAvailSats.Value = "—";
            edUsedSats.Value = "—";
            edTotalLink.Value = "—";
            edTotalDist.Value = "—";
            edStartEl.Value = "—";
            edEndEl.Value = "—";
            edATPDisplay.Value = "—";
            edTxPower.Value = "—";
            edStartTime.Value = "—";
            edEndTime.Value = "—";
            drawnow;

            % Update UI inputs to struct
            S.useNow = cbNow.Value;
            S.customTimeText = edTime.Value;
            S.maxDTE_km = edMaxDTE.Value;
            S.maxISL_km = edMaxISL.Value;
            S.minElevation_deg = edMinEl.Value;
            S.atpTime_ms = edATP.Value;
            S.openSolverGlobe = cbOpenGlobe.Value;
            
            % Parse Start Time
            if S.useNow
                t0 = datetime("now","TimeZone","UTC");
            else
                try
                    t0 = datetime(S.customTimeText, "InputFormat","yyyy-MM-dd HH:mm:ss", "TimeZone","UTC");
                catch
                    error("Invalid time format. Use yyyy-MM-dd HH:MM:SS");
                end
            end
            
            S.startLLA = parseLLAText(edStart.Value);
            S.endLLA   = parseLLAText(edEnd.Value);

            sel = string(lbRequest.Value);
            if isempty(sel)
                sel = "Tranche 0";
            end
            S.requestList = sel(:).';
            
            requestTag = strjoin(S.requestList, " + ");
            requestTagSafe = regexprep(requestTag, '[^\w\-\+]', '_');
            
            appendLog("Requests: " + requestTag);
            
            % 1) Get NORADs
            appendLog("Calling FXN_get_norad_ids...");
            [~, noradVec] = FXN_get_norad_ids(S.requestList, S.excelPath);
            appendLog("NORAD count: " + numel(noradVec));
            
            edAvailSats.Value = string(numel(noradVec));
            drawnow;

            % 2) Check/Download TLE
            appendLog("Checking recent TLE file...");
            [useExisting, existingFile] = FXN_check_recent_tle_file(requestTagSafe, S.expireDays);
            
            if useExisting
                S.outTLEFile = string(existingFile);
                appendLog("Using existing TLE file: " + S.outTLEFile);
            else
                appendLog("Downloading new TLE file...");
                S.outTLEFile = string(FXN_download_tles_request(requestTagSafe));
                appendLog("Downloaded TLE file: " + S.outTLEFile);
            end

            if strlength(S.outTLEFile) > 0 && isfile(S.outTLEFile)
                try
                    tleLines = splitlines(string(fileread(S.outTLEFile)));
                    tleArea.Value = tleLines(:);
                catch
                    tleArea.Value = "Error reading TLE file.";
                end
            end

            % 3) Solve shortest path
            cfg = struct();
            cfg.inFile               = S.outTLEFile;
            cfg.startLLA             = S.startLLA;
            cfg.endLLA               = S.endLLA;
            cfg.maxDTE_km            = S.maxDTE_km;
            cfg.maxISL_km            = S.maxISL_km;
            cfg.minElevation_deg     = S.minElevation_deg;
            cfg.sampleTime_s         = S.sampleTime_ms / 1000; 
            cfg.numberAttempts       = S.numberAttempts;
            cfg.t0                   = t0;
            cfg.outTxt               = S.hopsFile;
            cfg.plotWindow_minutes   = 30;
            cfg.make3DScenarioViewer = S.openSolverGlobe;   
            cfg.make2DMapFigure      = S.makeSolver2DFigure;
            cfg.mapBasemap           = S.mapBasemap;
            cfg.verbose              = true;

            appendLog("Calling FXN_solve_optical_shortest_path...");
            S.result = FXN_solve_optical_shortest_path(cfg);

            if ~isfield(S.result,"solved") || ~S.result.solved
                statusTxt = "Not solved";
                if isfield(S.result,"status"), statusTxt = string(S.result.status); end
                setStatus(statusTxt, false);
                edUsedSats.Value = "0";
            else
                setStatus("Solved @ " + string(S.result.tUse) + " — hops: " + height(S.result.HopTable), false);
                nUsedSats = max(0, height(S.result.HopTable) - 1);
                edUsedSats.Value = string(nUsedSats);
            end

            % 4) Compute link budget (using v1)
            if isfile(S.hopsFile)
                appendLog("Calling FXN_compute_optical_hop_table_v1...");
                
                passC = S.C;
                % Inject UI ATP time directly into the v1 Constants struct
                passC.t_atp_s = S.atpTime_ms / 1000; 
                passC.printTable = false;

                [Tlink, totalTime_s, meta_consts] = FXN_compute_optical_hop_table_v1(S.hopsFile, passC);
                
                % Print calculated meta constants to log output
                appendLog("--- Link Budget Fixed Constants ---");
                fields = fieldnames(meta_consts);
                for k = 1:numel(fields)
                    appendLog(sprintf("%s: %g", fields{k}, meta_consts.(fields{k})));
                end
                
                % Convert internal _s columns to _ms for user display
                varNames = Tlink.Properties.VariableNames;
                for c_idx = 1:numel(varNames)
                    col = varNames{c_idx};
                    if endsWith(col, "_s")
                        Tlink.(col) = Tlink.(col) .* 1000;
                        newCol = strrep(col, "_s", "_ms");
                        Tlink = renamevars(Tlink, col, newCol);
                    end
                end

                % Distance formatting
                distStr = "—";
                varsStr = string(Tlink.Properties.VariableNames);
                varsLow = lower(varsStr);
                
                candidates = ["distance_km", "range_km", "dist_km", "length_km", "distance", "range"];
                distCol = "";
                for c = candidates
                    idx = find(varsLow == c, 1);
                    if ~isempty(idx)
                        distCol = varsStr(idx);
                        break;
                    end
                end
                
                if distCol ~= ""
                    totalDist = sum(Tlink.(distCol), "omitnan");
                    distStr = sprintf("%.2f km", totalDist);
                else
                    try
                        totalDist = 0;
                        hTable = S.result.HopTable;
                        R = 6371e3;
                        for k = 1:height(hTable)
                            [x1,y1,z1] = llaToECEF_simple(hTable.From_lat_deg(k), hTable.From_lon_deg(k), hTable.From_alt_m(k), R);
                            [x2,y2,z2] = llaToECEF_simple(hTable.To_lat_deg(k), hTable.To_lon_deg(k), hTable.To_alt_m(k), R);
                            hopD_m = sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2);
                            totalDist = totalDist + (hopD_m / 1000);
                        end
                        distStr = sprintf("%.2f km", totalDist);
                    catch
                    end
                end
                edTotalDist.Value = distStr;

                % Dynamic Elevation formatting
                startElStr = "—";
                endElStr = "—";
                try
                    latGS  = S.result.HopTable.From_lat_deg(1);
                    lonGS  = S.result.HopTable.From_lon_deg(1);
                    altGS  = S.result.HopTable.From_alt_m(1);
                    latSat = S.result.HopTable.To_lat_deg(1);
                    lonSat = S.result.HopTable.To_lon_deg(1);
                    altSat = S.result.HopTable.To_alt_m(1);
                    
                    calcStartEl = computeElevationDeg(latGS, lonGS, altGS, latSat, lonSat, altSat);
                    startElStr = sprintf("%.2f deg", calcStartEl);
                    
                    latGS_end  = S.result.HopTable.To_lat_deg(end);
                    lonGS_end  = S.result.HopTable.To_lon_deg(end);
                    altGS_end  = S.result.HopTable.To_alt_m(end);
                    latSat_end = S.result.HopTable.From_lat_deg(end);
                    lonSat_end = S.result.HopTable.From_lon_deg(end);
                    altSat_end = S.result.HopTable.From_alt_m(end);
                    
                    calcEndEl = computeElevationDeg(latGS_end, lonGS_end, altGS_end, latSat_end, lonSat_end, altSat_end);
                    endElStr = sprintf("%.2f deg", calcEndEl);
                catch
                end

                edStartEl.Value = startElStr;
                edEndEl.Value   = endElStr;

                S.T_link = Tlink;
                
                % --- TRANSPOSE TABLE FOR UI ---
                varNames = Tlink.Properties.VariableNames;
                numRows = height(Tlink);
                numCols = numel(varNames);
                
                T_disp = table();
                T_disp.Parameter = string(varNames(:));
                
                for r_idx = 1:numRows
                    colName = sprintf('Hop_%d', r_idx);
                    rowVals = strings(numCols, 1);
                    for c_idx = 1:numCols
                        val = Tlink{r_idx, c_idx};
                        
                        if iscell(val)
                            val = val{1};
                        end
                        
                        if isdatetime(val)
                            strVal = string(val, "yyyy-MM-dd HH:mm:ss");
                        elseif isnumeric(val) || islogical(val)
                            strVal = string(num2str(val));
                        else
                            strVal = string(val);
                        end
                        
                        rowVals(c_idx) = strjoin(strVal, ", ");
                    end
                    T_disp.(colName) = rowVals;
                end

                hopTable.Data = T_disp;

                % Output new Tx Power mapping (GS and LCT)
                edATPDisplay.Value = sprintf("%g ms / hop", S.atpTime_ms);
                edTxPower.Value    = sprintf("GS: %g W, LCT: %g W", S.C.Pt_gs_W, S.C.Pt_lct_W);
                
                elapsed_s = toc(tStart);
                edElapsed.Value = sprintf("%.2f s", elapsed_s);

                N = height(S.T_link);
                nATP = max(N-1, 0);

                if isnumeric(totalTime_s) && isscalar(totalTime_s) && ~isnan(totalTime_s)
                    baseTime_ms = totalTime_s * 1000;
                elseif ismember("t_hop_ms", S.T_link.Properties.VariableNames)
                    baseTime_ms = sum(S.T_link.t_hop_ms, "omitnan");
                else
                    baseTime_ms = NaN;
                end

                totalLink_ms = baseTime_ms;

                if isnan(totalLink_ms)
                    edTotalLink.Value = "—";
                else
                    edTotalLink.Value = sprintf("%.2f ms", totalLink_ms);
                end
                
                if isfield(S.result, 'tUse') && isdatetime(S.result.tUse)
                    actualStart = S.result.tUse;
                else
                    actualStart = t0;
                end
                
                edStartTime.Value = string(actualStart, "yyyy-MM-dd HH:mm:ss");
                
                if ~isnan(totalLink_ms)
                    tEnd = actualStart + milliseconds(totalLink_ms);
                    edEndTime.Value = string(tEnd, "yyyy-MM-dd HH:mm:ss.SSS");
                else
                    edEndTime.Value = "—";
                end
            else
                appendLog("Hops file not found: " + S.hopsFile);
                hopTable.Data = table();
                
                edTotalDist.Value = "—";
                edStartEl.Value = "—";
                edEndEl.Value = "—";
                edATPDisplay.Value = "—";
                edTxPower.Value = "—";
                edStartTime.Value = "—";
                edEndTime.Value = "—";
                elapsed_s = toc(tStart);
                edElapsed.Value = sprintf("%.2f s", elapsed_s);
            end

            % 5) Update plots
            update2DMap();
            update3DGlobe();

            appendLog("Done.");

        catch ME
            setStatus("ERROR: " + string(ME.message), false);
            appendLog("ERROR: " + string(ME.message));
            
            elapsed_s = toc(tStart);
            edElapsed.Value = sprintf("%.2f s", elapsed_s);
        end
    end

    % -------------------------
    % Plot helpers
    % -------------------------
    function update2DMap()
        cla(gx);
        try
            geobasemap(gx, S.mapBasemap);
        catch
            geobasemap(gx, 'grayterrain');
        end
        hold(gx,"on");

        if isempty(S.result) || ~isfield(S.result,"HopTable") || height(S.result.HopTable)==0
            title(gx,"No hop data to plot");
            hold(gx,"off");
            return;
        end

        lat = [S.result.HopTable.From_lat_deg; S.result.HopTable.To_lat_deg(end)];
        lon = [S.result.HopTable.From_lon_deg; S.result.HopTable.To_lon_deg(end)];

        [latPlot, lonPlot] = splitDatelinePolyline(lat, lon);

        geoplot(gx, latPlot, lonPlot, "-r", "LineWidth", 2);
        geoscatter(gx, lat, lon, 40, "r", "filled");

        nodeNames = [S.result.HopTable.From; S.result.HopTable.To(end)];
        for i = 1:numel(nodeNames)
            text(gx, lat(i), lon(i), "  " + string(nodeNames(i)), ...
                "FontSize", 9, "Color","w", "Interpreter","none");
        end
        title(gx, "Optical Relay Path", "Interpreter","none");
        hold(gx,"off");
    end

    function update3DGlobe()
        cla(ax3);
        renderEmptyGlobe(ax3);
        hold(ax3,"on");

        if isempty(S.result) || ~isfield(S.result,"HopTable") || height(S.result.HopTable)==0
            title(ax3,"No hop data to render");
            hold(ax3,"off");
            return;
        end

        lat = [S.result.HopTable.From_lat_deg; S.result.HopTable.To_lat_deg(end)];
        lon = [S.result.HopTable.From_lon_deg; S.result.HopTable.To_lon_deg(end)];
        alt = [S.result.HopTable.From_alt_m;   S.result.HopTable.To_alt_m(end)];

        R = 6371e3;
        [x,y,z] = llaToECEF_simple(lat, lon, alt, R);

        plot3(ax3, x, y, z, "-r", "LineWidth", 2);
        scatter3(ax3, x, y, z, 40, "filled");

        nodeNames = [string(S.result.HopTable.From); string(S.result.HopTable.To(end))];
        for i = 1:numel(x)
            text(ax3, x(i), y(i), z(i), "  " + nodeNames(i), ...
                "Color", "w", ...                     
                "Interpreter", "none", ...            
                "BackgroundColor", [0.3 0.3 0.3], ... 
                "Margin", 1, ...
                "FontSize", 9);
        end
        title(ax3,"Used satellites & GS","Interpreter","none");
        hold(ax3,"off");
    end

    function setStatus(msg, busy)
        lblStatus.Text = "Status: " + string(msg);
        fig.Pointer = ternary(busy,"watch","arrow");
        drawnow;
    end

    function appendLog(msg)
        msg = string(msg);
        v = string(txtLog.Value);
        if isempty(v), v = strings(0,1); end
        v(end+1,1) = msg;
        txtLog.Value = v;
        try, txtLog.scroll("bottom"); catch, end
        drawnow;
    end
end

% =========================================================================
% Local Functions (Helpers)
% =========================================================================

function el_deg = computeElevationDeg(latGS, lonGS, altGS, latSat, lonSat, altSat)
    R = 6371e3;
    [x1, y1, z1] = llaToECEF_simple(latGS, lonGS, altGS, R);
    [x2, y2, z2] = llaToECEF_simple(latSat, lonSat, altSat, R);
    
    dx = x2 - x1;
    dy = y2 - y1;
    dz = z2 - z1;
    
    dist = sqrt(dx^2 + dy^2 + dz^2);
    
    lat_rad = deg2rad(latGS);
    lon_rad = deg2rad(lonGS);
    ux = cos(lat_rad) * cos(lon_rad);
    uy = cos(lat_rad) * sin(lon_rad);
    uz = sin(lat_rad);
    
    dot_prod = dx*ux + dy*uy + dz*uz;
    el_deg = asind(dot_prod / dist);
end

function C = defaultOpticalConstants()
    % Mapped directly to FXN_compute_optical_hop_table_v1 parameters
    C = struct();
    C.lambda_nm = 1550;
    C.theta_div_gs_urad = 10;
    C.theta_div_lct_urad = 15;
    C.D_tx_gs_mm = 200;
    C.D_rx_gs_mm = 200;
    C.D_tx_lct_mm = 80;
    C.D_rx_lct_mm = 80;
    C.Pt_gs_W = 5.0;
    C.Pt_lct_W = 1.0;
    C.eta_tx_gs_pct = 80;
    C.eta_rx_gs_pct = 80;
    C.eta_tx_lct_pct = 80;
    C.eta_rx_lct_pct = 80;
    C.dataRate_bps = 10e9;
    C.bits_per_symbol = 1; 
    C.packetBits = 1e6;
    C.theta_err_tx_urad = 1;
    C.theta_err_rx_urad = 1;
    C.Preq_dBm = -35.5;
    C.atm_att_coef = 0.1; 
    C.h_tropo_km = 20;
end

function s = llaToText(lla)
    s = sprintf("%.6f, %.6f, %.2f", lla(1), lla(2), lla(3));
end

function lla = parseLLAText(txt)
    s = string(txt);
    s = lower(s);
    s = replace(s, ["lat","lon","long","longitude","latitude","alt","altitude","="], " ");
    s = erase(s, ["(",")","[","]","{","}"]);
    s = replace(s, [";",","], " ");
    tokens = regexp(s, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
    if numel(tokens) < 2
        error("LLA parse failed. Provide at least lat and lon.");
    end
    lat = str2double(tokens{1});
    lon = str2double(tokens{2});
    if numel(tokens) >= 3, alt = str2double(tokens{3}); else, alt = 0; end
    if any(isnan([lat lon alt])), error("LLA contains NaN"); end
    lla = [lat lon alt];
end

function renderEmptyGlobe(ax)
    R = 6371e3;
    try
        d = load('topo.mat'); 
        d.topo = circshift(d.topo, [0, 180]); 
        [x,y,z] = sphere(50);
        
        props.FaceColor = 'texture';
        props.EdgeColor = 'none';
        props.CData = d.topo; 
        props.FaceLighting = 'gouraud';
        
        surface(ax, R*x, R*y, R*z, props);
        colormap(ax, demcmap(d.topo)); 
    catch
        [Xs,Ys,Zs] = sphere(20);
        surf(ax, R*Xs, R*Ys, R*Zs, "EdgeColor","none", "FaceAlpha", 0.85);
        colormap(ax, parula);
    end
    
    axis(ax,"equal");
    xlabel(ax,"X (m)"); ylabel(ax,"Y (m)"); zlabel(ax,"Z (m)");
    view(ax,3);
end

function [x,y,z] = llaToECEF_simple(lat_deg, lon_deg, alt_m, R)
    lat = deg2rad(lat_deg(:));
    lon = deg2rad(lon_deg(:));
    r = R + alt_m(:);
    x = r .* cos(lat) .* cos(lon);
    y = r .* cos(lat) .* sin(lon);
    z = r .* sin(lat);
end

function [latOut, lonOut] = splitDatelinePolyline(lat, lon)
    lat = lat(:); lon = lon(:);
    latOut = lat(1);
    lonOut = lon(1);
    for k = 2:numel(lat)
        dlon = lon(k) - lon(k-1);
        if abs(dlon) > 180
            latOut(end+1,1) = NaN; %#ok<AGROW>
            lonOut(end+1,1) = NaN; %#ok<AGROW>
        end
        latOut(end+1,1) = lat(k); %#ok<AGROW>
        lonOut(end+1,1) = lon(k); %#ok<AGROW>
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function applyDarkMode(fig)
    darkBG  = [0.16 0.16 0.16];
    panelBG = [0.20 0.20 0.20];
    white   = [1 1 1];
    try, fig.Color = darkBG; catch, end
    pans = findall(fig,"Type","uipanel");
    for k = 1:numel(pans)
        try
            pans(k).BackgroundColor = panelBG;
            pans(k).ForegroundColor = white; 
        catch
        end
    end
    labs = findall(fig,"Type","uilabel");
    for k = 1:numel(labs)
        try, labs(k).FontColor = darkBG; catch, end 
    end
end

% -----------------------------------------------------------
% Cities Catalogue Loader
% -----------------------------------------------------------
function [cities, cityNames] = loadCitiesCatalogue(xlsxPath, sheetName)
    if nargin < 2 || strlength(string(sheetName)) == 0
        sheetName = 1; 
    end

    if ~isfile(xlsxPath)
        error("Cities Excel file not found: %s", xlsxPath);
    end

    try
        opts = detectImportOptions(xlsxPath, "Sheet", sheetName);
        opts = setvaropts(opts, opts.VariableNames, "Type", "string"); 
        T = readtable(xlsxPath, opts);
        
        vars = string(T.Properties.VariableNames);
        if ~all(startsWith(vars, "Var"))
            [cities, cityNames] = buildCitiesFromTable(T);
            return;
        end
    catch
    end

    raw = readcell(xlsxPath, "Sheet", sheetName);
    headerRow = findHeaderRowCities(raw);
    headers = string(raw(headerRow, :));
    data    = raw(headerRow+1:end, :);

    cityCol = pickVar(headers, ["city","name","location"]);
    latCol  = pickVar(headers, ["latitude","lat","lat_deg"]);
    lonCol  = pickVar(headers, ["longitude","lon","long","lon_deg"]);
    altCol  = pickVar(headers, ["altitude","alt","alt_m","elevation"]);

    if cityCol==0 || latCol==0 || lonCol==0
        cities = table();
        cityNames = [];
        return;
    end
    
    city = string(data(:, cityCol)); 
    lat  = cellfun(@toNum, data(:, latCol)); 
    lon  = cellfun(@toNum, data(:, lonCol)); 
    
    if altCol==0
        alt = zeros(size(lat));
    else
        alt = cellfun(@toNum, data(:, altCol));
    end
    
    N = min([numel(city), numel(lat), numel(lon), numel(alt)]);
    city=city(1:N); lat=lat(1:N); lon=lon(1:N); alt=alt(1:N);
    
    ok = (city ~= "") & ~isnan(lat) & ~isnan(lon);
    cities = table(strtrim(city(ok)), lat(ok), lon(ok), alt(ok), ...
        'VariableNames', {'City','Lat_deg','Lon_deg','Alt_m'});
    
    cityNames = unique(cities.City, 'stable');
end

function [cities, cityNames] = buildCitiesFromTable(T)
    vars = lower(string(T.Properties.VariableNames));
    cityCol = pickVar(vars, ["city","name","location"]);
    latCol  = pickVar(vars, ["latitude","lat","lat_deg"]);
    lonCol  = pickVar(vars, ["longitude","lon","long","lon_deg"]);
    altCol  = pickVar(vars, ["altitude","alt","alt_m","elevation"]);

    if cityCol==0 || latCol==0 || lonCol==0
        error("Missing required city columns");
    end

    city = strtrim(string(T{:,cityCol}));
    lat  = double(str2double(string(T{:,latCol})));
    lon  = double(str2double(string(T{:,lonCol})));
    
    if altCol==0
        alt = zeros(height(T),1);
    else
        alt = double(str2double(string(T{:,altCol})));
        alt(isnan(alt)) = 0;
    end

    ok = (city ~= "") & ~isnan(lat) & ~isnan(lon);
    cities = table(city(ok), lat(ok), lon(ok), alt(ok), ...
        'VariableNames', {'City','Lat_deg','Lon_deg','Alt_m'});
    cityNames = unique(cities.City, "stable");
end

function idx = pickVar(vNames, candidates)
    idx = 0;
    vNames = lower(vNames);
    for c = candidates
        k = find(strcmp(vNames, c), 1);
        if ~isempty(k), idx = k; return; end
    end
    for c = candidates
        k = find(contains(vNames, c), 1);
        if ~isempty(k), idx = k; return; end
    end
end

function r = findHeaderRowCities(raw)
    r = 1;
    bestScore = -Inf;
    maxScan = min(10, size(raw,1));
    for i = 1:maxScan
        row = lower(string(raw(i,:)));
        row(ismissing(row)) = "";
        score = any(contains(row,"city"))*3 + any(contains(row,"lat"))*2 + any(contains(row,"lon"))*2;
        if score > bestScore
            bestScore = score;
            r = i;
        end
    end
end

function x = toNum(v)
    if isnumeric(v), x = double(v); return; end
    x = str2double(string(v));
end