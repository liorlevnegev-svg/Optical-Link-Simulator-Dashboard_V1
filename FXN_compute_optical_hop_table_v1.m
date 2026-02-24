function [T, totalTime_s, meta_consts] = FXN_compute_optical_hop_table_v1(hopsFile, C)
%COMPUTE_OPTICAL_HOP_TABLE_V1 Compute advanced optical link parameters per hop.
%
% Inputs
%   hopsFile (char/string): path to optical_link_hops.txt
%   C (struct): user-defined constants
% Outputs
%   T (table): per-hop results
%   totalTime_s (double): sum of hop times
%   meta_consts (struct): prints/saves the fixed hardware constants used

    arguments
        hopsFile (1,1) string
        C (1,1) struct
    end

    %% ---------------------------
    %  Parse hop TSV from file
    %% ---------------------------
    txt = fileread(hopsFile);
    
    % Extract TSV block after marker
    tsvStart = regexp(txt, '--- TSV TABLE ---', 'once');
    if isempty(tsvStart)
        error("TSV TABLE marker not found in %s", hopsFile);
    end
    tsvBlock = strtrim(extractAfter(txt, tsvStart));
    
    lines = splitlines(tsvBlock);
    lines = lines(~cellfun(@isempty, lines));
    dataLines = lines(2:end);
    
    formatSpec = '%f %s %s %f %f %f %f %f %f %f %f %f';
    Cdata = textscan(strjoin(dataLines,newline), formatSpec, 'Delimiter','\t');
    
    Traw = table();
    Traw.Hop           = double(Cdata{1});
    Traw.From          = string(Cdata{2});
    Traw.To            = string(Cdata{3});
    Traw.Range_km      = double(Cdata{4});
    Traw.RelVrad_mps   = double(Cdata{5});
    Traw.Alt1_m        = double(Cdata{9});
    Traw.Alt2_m        = double(Cdata{12});

    %% ---------------------------
    %  Classify hop type (DTE vs ISL)
    %% ---------------------------
    isGS_from = startsWith(Traw.From, "GS_", "IgnoreCase", true);
    isGS_to   = startsWith(Traw.To,   "GS_", "IgnoreCase", true);

    hopType = repmat("ISL", height(Traw), 1);
    hopType(isGS_from | isGS_to) = "DTE";

    txIsGS = isGS_from;
    rxIsGS = isGS_to;

    %% ---------------------------
    %  Unit Conversions & Constants
    %% ---------------------------
    c = 299792458;               % Speed of light [m/s]
    h = 6.626e-34;               % Planck's constant [J*s]
    lam_m = C.lambda_nm * 1e-9;  % Wavelength [m]
    nu = c / lam_m;              % Optical Frequency [Hz]
    E_ph = h * nu;               % Photon energy [J]
    
    R_m = Traw.Range_km * 1e3;   % Range [m]

    %% ---------------------------
    %  Assign Transceiver Parameters per Hop
    %% ---------------------------
    % Divergence (convert urad to rad)
    Theta_T_rad = zeros(height(Traw),1);
    Theta_T_rad(txIsGS)  = C.theta_div_gs_urad * 1e-6;
    Theta_T_rad(~txIsGS) = C.theta_div_lct_urad * 1e-6;

    % Transmitter Aperture (convert mm to m)
    D_T_m = zeros(height(Traw),1);
    D_T_m(txIsGS)  = C.D_tx_gs_mm * 1e-3;
    D_T_m(~txIsGS) = C.D_tx_lct_mm * 1e-3;

    % Receiver Aperture (convert mm to m)
    D_R_m = zeros(height(Traw),1);
    D_R_m(rxIsGS)  = C.D_rx_gs_mm * 1e-3;
    D_R_m(~rxIsGS) = C.D_rx_lct_mm * 1e-3;

    % Transmit Power [W]
    Pt_W = zeros(height(Traw),1);
    Pt_W(txIsGS)  = C.Pt_gs_W;
    Pt_W(~txIsGS) = C.Pt_lct_W;

    % Efficiencies [Linear from %]
    eta_T = zeros(height(Traw),1);
    eta_T(txIsGS)  = C.eta_tx_gs_pct / 100;
    eta_T(~txIsGS) = C.eta_tx_lct_pct / 100;

    eta_R = zeros(height(Traw),1);
    eta_R(rxIsGS)  = C.eta_rx_gs_pct / 100;
    eta_R(~rxIsGS) = C.eta_rx_lct_pct / 100;

    %% ---------------------------
    %  Physics Equations (From PDF)
    %% ---------------------------
    % (Eq 2) Transmitter Gain
    G_T = 16 ./ (Theta_T_rad.^2);
    G_T_dB = 10 * log10(G_T);

    % (Eq 3) Receiver Gain
    G_R = (pi .* D_R_m ./ lam_m).^2;
    G_R_dB = 10 * log10(G_R);

    % Pointing Errors [rad]
    theta_err_T = C.theta_err_tx_urad * 1e-6;
    theta_err_R = C.theta_err_rx_urad * 1e-6;

    % (Eq 4) Transmitter pointing loss
    L_T = exp(-G_T .* (theta_err_T^2));
    L_T_dB = -10 * log10(L_T); % Positive dB value representing loss

    % (Eq 5) Receiver pointing loss
    L_R = exp(-G_R .* (theta_err_R^2));
    L_R_dB = -10 * log10(L_R); % Positive dB value representing loss

    % (Eq 6 & 9) Free-space path loss
    L_FS = (lam_m ./ (4 * pi .* R_m)).^2;
    L_FS_dB = -10 * log10(L_FS); % Positive dB value representing loss

    % (Eq 19) Atmospheric Attenuation (DTE only)
    L_atm = ones(height(Traw),1); % Default 1 (no loss) for ISL
    
    % Approx Elevation Angle sine for Slant distance (d_A)
    % sin(elev) ~ Alt_sat / Range
    sat_alt_m = max(Traw.Alt1_m, Traw.Alt2_m); 
    sin_elev = max(0.1, sat_alt_m ./ R_m); % cap at 0.1 to avoid div by zero
    
    % d_A = distance in troposphere (km)
    d_A_km = C.h_tropo_km ./ sin_elev;
    
    idx_dte = hopType == "DTE";
    L_atm(idx_dte) = exp(-C.atm_att_coef .* d_A_km(idx_dte));
    L_atm_dB = -10 * log10(L_atm); % Positive dB value representing loss

    % (Eq 1 & 7 rearranged) Received Power [W]
    Pr_W = Pt_W .* G_T .* G_R .* L_T .* L_R .* L_FS .* eta_T .* eta_R .* L_atm;

    % Receiver Sensitivity [W]
    Preq_W = 1e-3 * 10^(C.Preq_dBm / 10);

    % (Eq 23) Link Margin [dB]
    LM_linear = Pr_W ./ Preq_W;
    LM_dB = 10 * log10(max(LM_linear, realmin));

    %% ---------------------------
    %  Communication Metrics
    %% ---------------------------
    % Data and Symbol Rates
    Rb = C.dataRate_bps;
    Rs = Rb / C.bits_per_symbol; 

    % SNR (Photons per bit) - Linear & dB
    SNR_lin = Pr_W ./ (E_ph * Rb);
    SNR_dB = 10 * log10(max(SNR_lin, realmin));

    % CNR (Carrier-to-Noise) - based on symbol rate bandwidth
    CNR_lin = Pr_W ./ (E_ph * Rs);
    CNR_dB = 10 * log10(max(CNR_lin, realmin));

    % BER (OOK Theoretical) & SER
    BER = 0.5 * erfc(sqrt(SNR_lin / 2));
    SER = 1 - (1 - BER).^C.bits_per_symbol;

    % Doppler Shift [GHz]
    fd_Hz = (Traw.RelVrad_mps ./ c) .* nu;
    fd_GHz = fd_Hz / 1e9;

    %% ---------------------------
    %  Latency Calculations (Eq 33, 34, 40)
    %% ---------------------------
    t_prop_s = R_m ./ c;
    t_prop_ms = t_prop_s * 1000;
    
    t_tx_s = C.packetBits / Rb;
    t_atp_s = C.t_atp_s * ones(height(Traw),1);
    
    t_hop_s = t_prop_s + t_tx_s + t_atp_s;
    totalTime_s = sum(t_hop_s);

    %% ---------------------------
    %  Build Output Table
    %% ---------------------------
    T = table();
    T.Hop = Traw.Hop;
    T.From = Traw.From;
    T.To = Traw.To;
    T.Type = hopType;

    T.Range_km = Traw.Range_km;
    T.Doppler_GHz = fd_GHz;
    
    T.TxGain_dB = G_T_dB;
    T.RxGain_dB = G_R_dB;
    T.TxPointLoss_dB = L_T_dB;
    T.RxPointLoss_dB = L_R_dB;
    T.FSPL_dB = L_FS_dB;
    T.AtmosphericLoss_dB = L_atm_dB;

    T.Pt_W = Pt_W;
    T.Pr_W = Pr_W;
    T.Pr_dBm = 10 * log10(max(Pr_W, realmin) / 1e-3);
    T.LinkMargin_dB = LM_dB;

    T.SNR_dB = SNR_dB;
    T.CNR_dB = CNR_dB;
    T.BER = BER;
    T.SER = SER;

    T.t_prop_ms = t_prop_ms;
    T.t_hop_s = t_hop_s;
    
    %% ---------------------------
    %  Save Fixed Metadata / Constants
    %% ---------------------------
    meta_consts = struct();
    meta_consts.Wavelength_nm = C.lambda_nm;
    meta_consts.DataRate_bps = C.dataRate_bps;
    meta_consts.PacketSize_bits = C.packetBits;
    meta_consts.BitsPerSymbol = C.bits_per_symbol;
    meta_consts.ReceiverSensitivity_dBm = C.Preq_dBm;
    
    if isfield(C,"printTable") && C.printTable
        disp("=== Fixed Hardware Constants ===");
        disp(meta_consts);
        disp("=== Optical Hop Link Budget Table ===");
        disp(T);
        fprintf("TOTAL end-to-end latency: %.6f s\n", totalTime_s);
    end
end