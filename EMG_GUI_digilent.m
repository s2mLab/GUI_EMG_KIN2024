function EMG_GUI_digilent()
% Digilent / MCC (USB-1208FS-PLUS) EMG GUI for real-time acquisition and display (2 channels)
%
% ONE popup selects the pair:
%   - AI0-1, AI1-2, AI2-3, AI3-4, AI4-5, AI5-6, AI6-7
%
% + Test mode (no hardware):
%   - streams simulated MVC and recording data
%   - also saves a simulated data file in tempdir

    % Create the GUI
    f = figure('Name','NI DAQ EMG Acquisition','NumberTitle','off', ...
        'Position',[100,100,900,700],'Units','normalized');

    %% Colours (EMG1 / EMG2)
    color_emg1 = [0 0.4470 0.7410];       % blue
    color_emg2 = [0.8500 0.3250 0.0980];  % orange
    alpha_overlay = 0.20;                  % overlay "transparency"
    setappdata(f,'color_emg1',color_emg1);
    setappdata(f,'color_emg2',color_emg2);
    setappdata(f,'alpha_overlay',alpha_overlay);

    %% Status & MVC text
    statusTxt = uicontrol(f,'Style','text','String','Connexion à Digilent/MCC...', ...
        'Units','normalized','Position',[0.05,0.94,0.35,0.04], ...
        'FontSize',12,'HorizontalAlignment','left');

    % Blinking REC indicator
    recTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.40,0.94,0.15,0.04], ...
        'FontSize',12,'FontWeight','bold','HorizontalAlignment','left', ...
        'ForegroundColor',[1 0 0]);
    setappdata(f,'recTxt',recTxt);
    setappdata(f,'recBlinkOn',false);

    mvcTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.58,0.94,0.4,0.04], ...
        'FontSize',12,'HorizontalAlignment','left','ForegroundColor',[0 0 0]);

    %% ONE popup: channel pair selector (auto-connect on change)
    pairList = arrayfun(@(k) sprintf('AI%d-%d',k,k+1), 0:6, 'UniformOutput', false);
    uicontrol(f,'Style','text','String','Paire EMG:', ...
        'Units','normalized','Position',[0.05,0.905,0.08,0.035],'HorizontalAlignment','left');

    popupPair = uicontrol(f,'Style','popupmenu','String',pairList, ...
        'Units','normalized','Position',[0.13,0.9,0.10,0.045], ...
        'FontSize',11,'Value',1, ...
        'Callback',@(~,~) connectDAQ()); % auto action on change
    setappdata(f,'popupPair',popupPair);

    %% Axes (2x2 grid): raw1, raw2, filt1, filt2
    ax_raw1 = axes(f,'Units','normalized','Position',[0.07,0.58,0.40,0.30]); hold(ax_raw1,'on');
    title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');
    hLine_raw1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1);

    ax_raw2 = axes(f,'Units','normalized','Position',[0.53,0.58,0.40,0.30]); hold(ax_raw2,'on');
    title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');
    hLine_raw2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2);

    ax_filt1 = axes(f,'Units','normalized','Position',[0.07,0.15,0.40,0.30]); hold(ax_filt1,'on');
    title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');

    ax_filt2 = axes(f,'Units','normalized','Position',[0.53,0.15,0.40,0.30]); hold(ax_filt2,'on');
    title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

    setappdata(f,'ax_raw1',ax_raw1);
    setappdata(f,'ax_raw2',ax_raw2);
    setappdata(f,'ax_filt1',ax_filt1);
    setappdata(f,'ax_filt2',ax_filt2);
    setappdata(f,'hLine_raw1',hLine_raw1);
    setappdata(f,'hLine_raw2',hLine_raw2);

    %% Sampling
    Fs = 2000;
    setappdata(f,'Fs',Fs);

    %% Controls (height reduced by 2)
    btnStart = uicontrol(f,'Style','togglebutton','String','⏺ Enregistrer', ...
        'Units','normalized','Position',[0.54,0.95,0.20,0.035],'FontSize',12, ...
        'Callback',@(src,~) startStopDAQ(src,statusTxt));
    setappdata(f,'btnStart',btnStart);

    btnTest = uicontrol(f,'Style','togglebutton','String','🧪 Test', ...
        'Units','normalized','Position',[0.46,0.95,0.07,0.035],'FontSize',11, ...
        'Callback',@(src,~) toggleTestMode(src,statusTxt));
    setappdata(f,'btnTest',btnTest);

    uicontrol(f,'Style','pushbutton','String','MVC 1', ...
        'Units','normalized','Position',[0.76,0.95,0.08,0.035],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,1));

    uicontrol(f,'Style','pushbutton','String','MVC 2', ...
        'Units','normalized','Position',[0.85,0.95,0.08,0.035],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,2));

    % Bottom buttons
    uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
        'Units','normalized','Position',[0.60,0.02,0.18,0.03],'FontSize',12, ...
        'Callback',@(~,~) exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2));

    uicontrol(f,'Style','pushbutton','String','Exporter CSV', ...
        'Units','normalized','Position',[0.80,0.02,0.18,0.03],'FontSize',12, ...
        'Callback',@(~,~) exportCSV(f));

    %% MCC configuration (stored)
    boardNum = 0;
    setappdata(f,'boardNum',boardNum);

    gain = 1;
    try
        if exist('BIP10VOLTS','var') %#ok<EXIST>
            gain = BIP10VOLTS;
        end
    catch
    end
    setappdata(f,'gain',gain);

    %% Shared state
    setappdata(f,'mvc_values',[0 0]);
    setappdata(f,'rec_count',0);
    setappdata(f,'recordings_raw',{});
    setappdata(f,'liveTimer',[]);
    setappdata(f,'rawBuf',[]);
    setappdata(f,'sampleIdx',0);
    setappdata(f,'test_mode',false);
    setappdata(f,'autoStopping',false);

    % Sim data placeholders
    setappdata(f,'sim_data',[]);
    setappdata(f,'sim_idx_record',1);

    % Initial connection
    connectDAQ();
    setappdata(f,'connectFcn', @connectDAQ);

    %% ------- Nested: (Re)connect -------
    function connectDAQ()
        try
            % Stop any live timer
            t = getappdata(f,'liveTimer');
            if ~isempty(t) && isa(t,'timer') && isvalid(t)
                try stop(t); catch, end
                try delete(t); catch, end
            end
            setappdata(f,'liveTimer',[]);

            test_mode = getappdata(f,'test_mode');

            % Pair selection -> channels (always stored even in test mode)
            pairIdx = get(getappdata(f,'popupPair'),'Value'); % 1..7 => AI0-1..AI6-7
            ch1 = pairIdx - 1;
            ch2 = ch1 + 1;
            setappdata(f,'chanNum1',ch1);
            setappdata(f,'chanNum2',ch2);

            if test_mode
                set(statusTxt,'String',sprintf('Mode TEST (simulé) | paire AI%d-%d',ch1,ch2), ...
                    'ForegroundColor',[0.2 0.2 0.2]);
                return
            end

            % Hardware ping (MCC)
            try cbErrHandling(0,0); catch, end
            boardNum = getappdata(f,'boardNum');
            gain     = getappdata(f,'gain');

            [err1, ~] = cbAIn(boardNum, ch1, gain);
            [err2, ~] = cbAIn(boardNum, ch2, gain);
            if err1 ~= 0 || err2 ~= 0
                error('MCC cbAIn error (err1=%d, err2=%d).', err1, err2);
            end

            set(statusTxt,'String',sprintf('Digilent/MCC connecté (USB-1208FS-PLUS) | paire AI%d-%d',ch1,ch2), ...
                'ForegroundColor','green');

        catch ME
            set(statusTxt,'String','Échec de connexion Digilent/MCC','ForegroundColor','red');
            disp(getReport(ME,'extended'));
        end
    end

    %% ------- Nested: toggle test mode -------
    function toggleTestMode(src, statusTxtLocal)
        % If currently recording, stop first
        btnStartLocal = getappdata(f,'btnStart');
        if ~isempty(btnStartLocal) && isvalid(btnStartLocal) && btnStartLocal.Value == 1
            btnStartLocal.Value = 0;
            startStopDAQ(btnStartLocal, statusTxtLocal);
        end

        if src.Value == 1
            setappdata(f,'test_mode',true);

            % Build and save sim data file (requested)
            sim = buildSimData(getappdata(f,'Fs'));
            setappdata(f,'sim_data',sim);
            setappdata(f,'sim_idx_record',1);

            simFile = fullfile(tempdir,'EMG_simulated_data.mat');
            try
                save(simFile,'sim');
            catch
            end
            setappdata(f,'sim_file',simFile);

            set(statusTxtLocal,'String','Mode TEST activé (données simulées).','ForegroundColor',[0.2 0.2 0.2]);
        else
            setappdata(f,'test_mode',false);
            setappdata(f,'sim_data',[]);
            setappdata(f,'sim_idx_record',1);
            set(statusTxtLocal,'String','Mode TEST désactivé.','ForegroundColor',[0.2 0.2 0.2]);
        end

        connectDAQ();
    end
end

function startStopDAQ(src,statusTxt)
    fig = ancestor(src,'figure');

    boardNum = getappdata(fig,'boardNum');
    gain     = getappdata(fig,'gain');
    Fs       = getappdata(fig,'Fs');

    ax_raw1   = getappdata(fig,'ax_raw1');
    ax_raw2   = getappdata(fig,'ax_raw2');
    ax_filt1  = getappdata(fig,'ax_filt1');
    ax_filt2  = getappdata(fig,'ax_filt2');
    hLine1    = getappdata(fig,'hLine_raw1');
    hLine2    = getappdata(fig,'hLine_raw2');

    popupPair = getappdata(fig,'popupPair');
    recTxt    = getappdata(fig,'recTxt');

    color_emg1 = getappdata(fig,'color_emg1');
    color_emg2 = getappdata(fig,'color_emg2');
    alpha_overlay = getappdata(fig,'alpha_overlay');

    test_mode = getappdata(fig,'test_mode');

    ch1 = getappdata(fig,'chanNum1');
    ch2 = getappdata(fig,'chanNum2');
    if isempty(ch1) || isempty(ch2)
        set(statusTxt,'String','Canaux non définis. Changez la paire.','ForegroundColor','red');
        return
    end

    windowPts = Fs * 5;   % show last 5 s
    chunkPts  = 200;      % ~0.1 s at 2kHz

    if src.Value
        % --- START ---
        setappdata(fig,'rawBuf',[]);
        setappdata(fig,'sampleIdx',0);

        src.String = '⏹ Stop';
        set(popupPair,'Enable','off');

        set(recTxt,'String','REC ●');
        setappdata(fig,'recBlinkOn',true);

        % Clear panes
        cla(ax_raw1); hold(ax_raw1,'on'); title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');
        cla(ax_raw2); hold(ax_raw2,'on'); title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

        % Live lines
        hLine1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1); setappdata(fig,'hLine_raw1',hLine1);
        hLine2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2); setappdata(fig,'hLine_raw2',hLine2);

        set(ax_raw1,'XLim',[0, 5]);
        set(ax_raw2,'XLim',[0, 5]);

        % Reset sim index if in test mode
        if test_mode
            setappdata(fig,'sim_idx_record',1);
        end

        t = timer('ExecutionMode','fixedSpacing', ...
            'Period', chunkPts/Fs, ...
            'TimerFcn', @processLiveTick, ...
            'ErrorFcn',  @onTimerError);
        setappdata(fig,'liveTimer',t);
        start(t);

    else
        % --- STOP ---
        src.String = '⏺ Enregistrer';
        set(popupPair,'Enable','on');

        set(recTxt,'String','');
        setappdata(fig,'recBlinkOn',false);

        t = getappdata(fig,'liveTimer');
        if ~isempty(t) && isa(t,'timer') && isvalid(t)
            try stop(t); catch, end
            try delete(t); catch, end
        end
        setappdata(fig,'liveTimer',[]);

        rawBuf = getappdata(fig,'rawBuf');

        if ~isempty(rawBuf)
            emg1_raw = rawBuf(:,1);
            emg2_raw = rawBuf(:,2);

            filt1 = filterEMG(emg1_raw, Fs);
            filt2 = filterEMG(emg2_raw, Fs);

            mvc = getappdata(fig,'mvc_values');
            if ~isempty(mvc)
                if numel(mvc)>=1 && mvc(1)>0, filt1 = 100 * (filt1 / mvc(1)); end
                if numel(mvc)>=2 && mvc(2)>0, filt2 = 100 * (filt2 / mvc(2)); end
            end

            tsec_raw  = (0:numel(emg1_raw)-1)/Fs;
            tsec_filt = (0:numel(filt1)-1)/Fs;

            % FULL raw with overlay
            cla(ax_raw1); hold(ax_raw1,'on');
            plot(ax_raw1, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
            h = plot(ax_raw1, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
            title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');

            cla(ax_raw2); hold(ax_raw2,'on');
            plot(ax_raw2, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
            h = plot(ax_raw2, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
            title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');

            % Filtered (%MVC) with overlay
            cla(ax_filt1); hold(ax_filt1,'on');
            plot(ax_filt1, tsec_filt, filt1, '-', 'Color', color_emg1);
            h = plot(ax_filt1, tsec_filt, filt2, '-', 'Color', color_emg2);
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
            title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');

            cla(ax_filt2); hold(ax_filt2,'on');
            plot(ax_filt2, tsec_filt, filt2, '-', 'Color', color_emg2);
            h = plot(ax_filt2, tsec_filt, filt1, '-', 'Color', color_emg1);
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
            title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

            % Save recordings
            rec_count = getappdata(fig,'rec_count');
            rec_count = rec_count + 1;
            setappdata(fig,'rec_count',rec_count);

            recs = getappdata(fig,'recordings_raw');
            recs{rec_count} = rawBuf; %#ok<AGROW>
            setappdata(fig,'recordings_raw',recs);

            baseRawVar = sprintf('EMG_recording_raw_%02d',rec_count);
            baseF1Var  = sprintf('EMG1_filtered_%02d',rec_count);
            baseF2Var  = sprintf('EMG2_filtered_%02d',rec_count);

            assignin('base', baseRawVar, rawBuf);
            assignin('base', baseF1Var,  filt1);
            assignin('base', baseF2Var,  filt2);

            assignin('base','EMG_data_raw', rawBuf);
            assignin('base','EMG1_filtered', filt1);
            assignin('base','EMG2_filtered', filt2);

            disp(['Enregistrement #',num2str(rec_count),' sauvegardé (variables : ', ...
                baseRawVar,', ',baseF1Var,', ',baseF2Var,').']);
        else
            disp('Aucune donnée enregistrée.');
        end
    end

    function processLiveTick(~,~)
        rawBuf    = getappdata(fig,'rawBuf');
        sampleIdx = getappdata(fig,'sampleIdx');

        if test_mode
            sim = getappdata(fig,'sim_data');
            if isempty(sim)
                sim = buildSimData(Fs);
                setappdata(fig,'sim_data',sim);
                setappdata(fig,'sim_idx_record',1);
            end

            idx0 = getappdata(fig,'sim_idx_record');
            idx1 = idx0 + chunkPts - 1;

            if idx1 > numel(sim.rec1)
                % End of simulated record -> auto stop once
                if ~getappdata(fig,'autoStopping')
                    setappdata(fig,'autoStopping',true);
                    tlocal = getappdata(fig,'liveTimer');
                    if ~isempty(tlocal) && isa(tlocal,'timer') && isvalid(tlocal)
                        try stop(tlocal); catch, end
                        try delete(tlocal); catch, end
                    end
                    setappdata(fig,'liveTimer',[]);
                    setappdata(fig,'autoStopping',false);

                    % flip button + call stop branch
                    src.Value = 0;
                    startStopDAQ(src,statusTxt);
                end
                return
            end

            v1 = sim.rec1(idx0:idx1);
            v2 = sim.rec2(idx0:idx1);
            setappdata(fig,'sim_idx_record',idx1+1);
        else
            v1 = acquireOneChannel(boardNum, ch1, gain, Fs, chunkPts);
            v2 = acquireOneChannel(boardNum, ch2, gain, Fs, chunkPts);
        end

        volts = [v1(:), v2(:)];

        rawBuf = [rawBuf; volts]; %#ok<AGROW>
        setappdata(fig,'rawBuf',rawBuf);

        N = size(volts,1);
        sampleIdx = sampleIdx + N;
        setappdata(fig,'sampleIdx',sampleIdx);

        totalPts = sampleIdx;
        if totalPts <= windowPts
            idx = 1:totalPts;
        else
            idx = (totalPts-windowPts+1):totalPts;
        end

        tsec = (idx-idx(1))/Fs; % 0..5s window
        ch1win = rawBuf(idx,1);
        ch2win = rawBuf(idx,2);

        active1 = (std(double(ch1win)) > 1e-6) || (max(abs(ch1win)) > 1e-5);
        active2 = (std(double(ch2win)) > 1e-6) || (max(abs(ch2win)) > 1e-5);

        if active1
            set(hLine1,'XData',tsec,'YData',ch1win,'Color',color_emg1);
            set(ax_raw1,'XLim',[0, 5]);
        else
            set(hLine1,'XData',nan,'YData',nan);
        end

        if active2
            set(hLine2,'XData',tsec,'YData',ch2win,'Color',color_emg2);
            set(ax_raw2,'XLim',[0, 5]);
        else
            set(hLine2,'XData',nan,'YData',nan);
        end

        % Blink REC
        blink = getappdata(fig,'recBlinkOn');
        if blink
            set(recTxt,'String','');
        else
            set(recTxt,'String','REC ●');
        end
        setappdata(fig,'recBlinkOn',~blink);

        drawnow limitrate;
    end

    function onTimerError(~,evt)
        set(statusTxt,'String','Erreur acquisition (timer).','ForegroundColor','red');
        disp(evt.Data);
    end
end

function v = acquireOneChannel(boardNum, physCh, gain, Fs, nPts)
    try cbErrHandling(0,0); catch, end

    memHandle = cbWinBufAlloc(nPts);
    if memHandle == 0
        error('Erreur allocation buffer MCC (cbWinBufAlloc).');
    end

    try
        err = cbAInScan(boardNum, physCh, physCh, nPts, Fs, gain, memHandle, 0);
        if err ~= 0
            cbWinBufFree(memHandle);
            error('Erreur MCC cbAInScan (err=%d) sur AI%d.', err, physCh);
        end

        rawCounts = cbWinBufToArray(memHandle, nPts);
        cbWinBufFree(memHandle);

        rawCounts = double(rawCounts(:));

        if exist('cbToEngUnits','file') == 2
            v = zeros(size(rawCounts));
            for i = 1:numel(rawCounts)
                [err2, eng] = cbToEngUnits(boardNum, gain, rawCounts(i));
                if err2 ~= 0
                    v(i) = (rawCounts(i) - 2048) / 2048 * 10;
                else
                    v(i) = eng;
                end
            end
        else
            v = (rawCounts - 2048) / 2048 * 10; % approx for 12-bit bipolar ±10V
        end

    catch ME
        try cbWinBufFree(memHandle); catch, end
        rethrow(ME);
    end
end

function measureMVC(figHandle,mvcTxt,chIdx)
    Fs = getappdata(figHandle,'Fs');

    % stop live timer if any
    t = getappdata(figHandle,'liveTimer');
    if ~isempty(t) && isa(t,'timer') && isvalid(t)
        try stop(t); catch, end
        try delete(t); catch, end
    end
    setappdata(figHandle,'liveTimer',[]);

    test_mode = getappdata(figHandle,'test_mode');

    ch1 = getappdata(figHandle,'chanNum1'); if isempty(ch1), ch1 = 0; end
    ch2 = getappdata(figHandle,'chanNum2'); if isempty(ch2), ch2 = 1; end

    ax_raw1  = getappdata(figHandle,'ax_raw1');
    ax_raw2  = getappdata(figHandle,'ax_raw2');
    ax_filt1 = getappdata(figHandle,'ax_filt1');
    ax_filt2 = getappdata(figHandle,'ax_filt2');

    color_emg1 = getappdata(figHandle,'color_emg1');
    color_emg2 = getappdata(figHandle,'color_emg2');

    if chIdx==1
        targetRaw = ax_raw1; targetFilt = ax_filt1; physCh = ch1; side = 1; col = color_emg1; %#ok<NASGU>
    else
        targetRaw = ax_raw2; targetFilt = ax_filt2; physCh = ch2; side = 2; col = color_emg2; %#ok<NASGU>
    end

    durSec = 5;
    nPts   = Fs * durSec;

    set(mvcTxt,'String',sprintf('Mesure MVC%d en cours (5 s)...',side)); drawnow;

    if test_mode
        sim = getappdata(figHandle,'sim_data');
        if isempty(sim)
            sim = buildSimData(Fs);
            setappdata(figHandle,'sim_data',sim);
        end
        if side == 1
            buf = sim.mvc1(:);
        else
            buf = sim.mvc2(:);
        end
        buf = buf(1:min(nPts,numel(buf)));
    else
        boardNum = getappdata(figHandle,'boardNum');
        gain     = getappdata(figHandle,'gain');
        buf = acquireOneChannel(boardNum, physCh, gain, Fs, nPts);
    end

    tsec = (0:numel(buf)-1)/Fs;

    cla(targetRaw);  hold(targetRaw,'on');
    cla(targetFilt); hold(targetFilt,'on');
    title(targetRaw, sprintf('EMG%d MVC (%ds)', side, durSec));
    xlabel(targetRaw,'Temps (s)'); ylabel(targetRaw,'Activité (V)');
    title(targetFilt, sprintf('EMG%d enveloppe MVC', side));
    xlabel(targetFilt,'Temps (s)'); ylabel(targetFilt,'(%MVC)');

    plot(targetRaw, tsec, buf, '-');

    envFull = sqrt(movmean((buf - mean(buf)).^2, 100));
    plot(targetFilt, tsec, envFull, '-');

    nTake = min(2000, numel(buf));
    topVals = maxk(abs(buf), nTake);
    mvcVal = median(topVals);

    mvcLoc = getappdata(figHandle,'mvc_values'); if isempty(mvcLoc), mvcLoc = [0 0]; end
    mvcLoc(side) = mvcVal;
    setappdata(figHandle,'mvc_values', mvcLoc);

    set(mvcTxt,'String',sprintf('MVC1 = %.2f | MVC2 = %.2f',mvcLoc(1),mvcLoc(2)));
end

function filtered = filterEMG(raw, Fs)
    raw = raw - mean(raw);

    f0 = 60;
    Q  = 2;

    [b,a] = designNotchPeakIIR('Response','notch','CenterFrequency',f0,'QualityFactor',Q,'SampleRate',Fs);
    emg_notch = filtfilt(b,a, raw);

    [b,a] = butter(4, [20 400]/(Fs/2), 'bandpass');
    emg = filtfilt(b,a,emg_notch);

    filtered = sqrt(movmean(emg.^2,100));
end

function exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2)
    fig = figure('Visible','off','Position',[100,100,1200,800]);
    subplot(2,2,1);
    copyobj(allchild(ax_raw1), gca);
    title('EMG1 brut'); xlabel('Temps (s)'); ylabel('Activité (V)');

    subplot(2,2,2);
    copyobj(allchild(ax_raw2), gca);
    title('EMG2 brut'); xlabel('Temps (s)'); ylabel('Activité (V)');

    subplot(2,2,3);
    copyobj(allchild(ax_filt1), gca);
    title('EMG1 filtré (normalisé)'); xlabel('Temps (s)'); ylabel('(%MVC)');

    subplot(2,2,4);
    copyobj(allchild(ax_filt2), gca);
    title('EMG2 filtré (normalisé)'); xlabel('Temps (s)'); ylabel('(%MVC)');

    [file,path] = uiputfile('*.png','Exporter les graphiques sous...');
    if ~isequal(file,0)
        saveas(fig, fullfile(path,file));
        disp(['Graphiques exportés vers : ', fullfile(path,file)]);
    else
        disp('Exportation annulée.');
    end
    close(fig);
end

function exportCSV(figHandle)
    Fs = getappdata(figHandle,'Fs');

    recs = getappdata(figHandle,'recordings_raw');
    if isempty(recs)
        disp('Aucun enregistrement à exporter.');
        return
    end

    rawBuf = recs{end}; % export the latest
    if isempty(rawBuf) || size(rawBuf,2) < 2
        disp('Enregistrement invalide.');
        return
    end

    emg1_raw = rawBuf(:,1);
    emg2_raw = rawBuf(:,2);

    filt1 = filterEMG(emg1_raw, Fs);
    filt2 = filterEMG(emg2_raw, Fs);

    mvc = getappdata(figHandle,'mvc_values');
    if ~isempty(mvc)
        if numel(mvc)>=1 && mvc(1)>0, filt1 = 100 * (filt1 / mvc(1)); end
        if numel(mvc)>=2 && mvc(2)>0, filt2 = 100 * (filt2 / mvc(2)); end
    end

    t = (0:size(rawBuf,1)-1)'/Fs;

    T = table(t, emg1_raw, emg2_raw, filt1, filt2, ...
        'VariableNames', {'time_s','emg1_raw_V','emg2_raw_V','emg1_filt_pctMVC','emg2_filt_pctMVC'});

    [file,path] = uiputfile('*.csv','Exporter CSV sous...');
    if isequal(file,0)
        disp('Export CSV annulé.');
        return
    end
    out = fullfile(path,file);
    writetable(T,out);
    disp(['CSV exporté : ', out]);
end

function setLineAlphaOrLighten(h, rgb, alpha)
    try
        set(h,'Color',[rgb alpha]); % true alpha if supported
    catch
        rgb2 = rgb + (1 - rgb) * (1 - alpha); % lighten toward white
        set(h,'Color',rgb2);
    end
end

function sim = buildSimData(Fs)
% Générateur EMG simulé
% - Signal centré à 0
% - Amplitude modulée (enveloppe)
% - Bruit blanc
% - Parasite 60 Hz sur muscle 2 uniquement

    rng(1); % reproductible

    noiseStd = 0.2;      % bruit RMS (V)
    f_carrier = 80;      % pseudo-EMG (Hz)
    f_line = 60;         % secteur (Hz)

    %% ---------- MVC (5 s): rampe 1s, plateau 3s, repos 1s ----------
    durMVC = 5;
    Nmvc = durMVC * Fs;
    tMVC = (0:Nmvc-1)'/Fs;

    % Enveloppe MVC (0 → 1 → 0)
    envMVC = zeros(Nmvc,1);
    n1 = 1*Fs; n2 = 3*Fs; n3 = 1*Fs;
    envMVC(1:n1) = linspace(0,1,n1)';
    envMVC(n1+1:n1+n2) = 1;
    envMVC(n1+n2+1:n1+n2+n3) = 0;

    % Porteuse EMG (zéro moyenne)
    carrier1 = randn(Nmvc,1);
    carrier2 = randn(Nmvc,1);

    % Amplitudes MVC
    A1 = 2.0;   % muscle 1
    A2 = 3.0;   % muscle 2

    mvc1 = A1 * envMVC .* carrier1 + noiseStd*randn(Nmvc,1);
    mvc2 = A2 * envMVC .* carrier2 + noiseStd*randn(Nmvc,1) ...
           + 0.3*sin(2*pi*f_line*tMVC); % 60 Hz UNIQUEMENT muscle 2

    % Centrage explicite (sécurité)
    mvc1 = mvc1 - mean(mvc1);
    mvc2 = mvc2 - mean(mvc2);

    %% ---------- Enregistrement (5 s) ----------
    durRec = 5;
    Nrec = durRec * Fs;
    tRec = (0:Nrec-1)'/Fs;

    rec1 = noiseStd*randn(Nrec,1);
    rec2 = noiseStd*randn(Nrec,1) + 0.3*sin(2*pi*f_line*tRec); % 60 Hz muscle 2

    carrier1 = randn(Nrec,1);
    carrier2 = randn(Nrec,1);

    % Muscle 1 : 2 bouffées, 1.5 V, 1 s
    burstA1 = 1.5;
    burstDur1 = 1.0; nb1 = round(burstDur1*Fs);
    starts1 = round([1.0, 3.0]*Fs);

    for s = starts1
        idx = s + (1:nb1);
        idx(idx>Nrec) = [];
        env = ones(numel(idx),1);
        rec1(idx) = rec1(idx) + burstA1 * env .* carrier1(idx);
    end

    % Muscle 2 : 4 bouffées, 0.5 V, 0.7 s
    burstA2 = 0.5;
    burstDur2 = 0.7; nb2 = round(burstDur2*Fs);
    starts2 = round([0.6, 1.7, 2.8, 3.9]*Fs);

    for s = starts2
        idx = s + (1:nb2);
        idx(idx>Nrec) = [];
        env = ones(numel(idx),1);
        rec2(idx) = rec2(idx) + burstA2 * env .* carrier2(idx);
    end

    % Centrage explicite
    rec1 = rec1 - mean(rec1);
    rec2 = rec2 - mean(rec2);

    %% ---------- Sortie ----------
    sim = struct();
    sim.Fs   = Fs;
    sim.tMVC = tMVC;
    sim.mvc1 = mvc1;
    sim.mvc2 = mvc2;
    sim.tRec = tRec;
    sim.rec1 = rec1;
    sim.rec2 = rec2;
end
