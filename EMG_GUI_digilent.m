function EMG_GUI_digilent()
    % Digilent / MCC (USB-1208FS-PLUS) EMG GUI for real-time acquisition and display (2 channels)
    %
    % Confirmed setup: USB-1208FS-PLUS, 2 channels (AI0 & AI1) wired in DIFFERENTIAL:
    %   EMG1: AI0+ (signal) / AI0- (Grass GND)
    %   EMG2: AI1+ (signal) / AI1- (Grass GND)
    %
    % Requirements:
    %   - MCC Universal Library installed + MATLAB interface on path
    %   - Functions available: cbAIn, cbAInScan, cbWinBufAlloc, cbWinBufToArray, cbWinBufFree
    %   - Optional for exact volts: cbToEngUnits

    % Create the GUI
    f = figure('Name','NI DAQ EMG Acquisition','NumberTitle','off', ...
               'Position',[100,100,900,700],'Units','normalized');

    %% Status & MVC text
    statusTxt = uicontrol(f,'Style','text','String','Connexion à Digilent/MCC...', ...
        'Units','normalized','Position',[0.05,0.94,0.5,0.04], ...
        'FontSize',12,'HorizontalAlignment','left');
    mvcTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.58,0.94,0.4,0.04], ...
        'FontSize',12,'HorizontalAlignment','left','ForegroundColor',[0 0 0]);

    %% Channel choosers + (Re)connect
    devList = arrayfun(@(k) sprintf('AI%d',k), 0:7, 'UniformOutput', false);
    uicontrol(f,'Style','text','String','EMG1 canal:', ...
        'Units','normalized','Position',[0.05,0.905,0.08,0.035],'HorizontalAlignment','left');
    popupDev1 = uicontrol(f,'Style','popupmenu','String',devList, ...
        'Units','normalized','Position',[0.13,0.9,0.08,0.045], 'FontSize',11, 'Value',1); % AI0

    uicontrol(f,'Style','text','String','EMG2 canal:', ...
        'Units','normalized','Position',[0.22,0.905,0.08,0.035],'HorizontalAlignment','left');
    popupDev2 = uicontrol(f,'Style','popupmenu','String',devList, ...
        'Units','normalized','Position',[0.30,0.9,0.08,0.045], 'FontSize',11, 'Value',2); % AI1

    btnReconnect = uicontrol(f,'Style','pushbutton','String','(Re)connecter', ...
        'Units','normalized','Position',[0.40,0.9,0.12,0.05],'FontSize',11, ...
        'Callback',@(~,~) connectDAQ());

    %% Axes (2x2 grid): raw1, raw2, filt1, filt2
    ax_raw1 = axes(f,'Units','normalized','Position',[0.07,0.58,0.40,0.30]); hold(ax_raw1,'on');
    title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Échantillon'); ylabel(ax_raw1,'Amplitude');
    hLine_raw1 = plot(ax_raw1,nan,nan,'-');

    ax_raw2 = axes(f,'Units','normalized','Position',[0.53,0.58,0.40,0.30]); hold(ax_raw2,'on');
    title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Échantillon'); ylabel(ax_raw2,'Amplitude');
    hLine_raw2 = plot(ax_raw2,nan,nan,'-');

    ax_filt1 = axes(f,'Units','normalized','Position',[0.07,0.15,0.40,0.30]); hold(ax_filt1,'on');
    title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Échantillon'); ylabel(ax_filt1,'Amplitude');

    ax_filt2 = axes(f,'Units','normalized','Position',[0.53,0.15,0.40,0.30]); hold(ax_filt2,'on');
    title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Échantillon'); ylabel(ax_filt2,'Amplitude');

    %% Controls
    btnStart = uicontrol(f,'Style','togglebutton','String','Commencer l''enregistrement', ...
        'Units','normalized','Position',[0.54,0.9,0.20,0.05],'FontSize',12, ...
        'Callback',@(src,~) startStopDAQ(src,statusTxt));

    uicontrol(f,'Style','pushbutton','String','MVC 1', ...
        'Units','normalized','Position',[0.76,0.9,0.08,0.05],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,1));
    uicontrol(f,'Style','pushbutton','String','MVC 2', ...
        'Units','normalized','Position',[0.85,0.9,0.08,0.05],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,2));

    uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
        'Units','normalized','Position',[0.83,0.84,0.15,0.05],'FontSize',12, ...
        'Callback',@(~,~) exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2));

    %% MCC configuration (stored)
    boardNum = 0;
    setappdata(f,'boardNum',boardNum);

    % Gain/range:
    % - If your UL binding defines BIP10VOLTS, use that.
    % - Otherwise, keep gain=1 (common mapping for ±10 V in several MATLAB UL bindings).
    gain = 1;
    try
        if exist('BIP10VOLTS','var') %#ok<EXIST>
            gain = BIP10VOLTS;
        end
    catch
    end
    setappdata(f,'gain',gain);

    % Sampling
    Fs = 2000;
    setappdata(f,'Fs',Fs);

    % Store shared GUI objects
    setappdata(f,'popupDev1',popupDev1);
    setappdata(f,'popupDev2',popupDev2);

    setappdata(f,'ax_raw1',ax_raw1);
    setappdata(f,'ax_raw2',ax_raw2);
    setappdata(f,'ax_filt1',ax_filt1);
    setappdata(f,'ax_filt2',ax_filt2);
    setappdata(f,'hLine_raw1',hLine_raw1);
    setappdata(f,'hLine_raw2',hLine_raw2);

    setappdata(f,'mvc_values',[0 0]);
    setappdata(f,'mvc_waveforms',struct('raw1',[],'raw2',[],'env1',[],'env2',[]));

    setappdata(f,'rec_count',0);
    setappdata(f,'recordings_raw',{});

    setappdata(f,'liveTimer',[]);
    setappdata(f,'rawBuf',[]);
    setappdata(f,'sampleIdx',0);

    connectDAQ();
    setappdata(f,'connectFcn', @connectDAQ);

    %% Nested: (Re)connect
    function connectDAQ()
        try
            % Stop any live timer
            t = getappdata(f,'liveTimer');
            if ~isempty(t) && isa(t,'timer') && isvalid(t)
                try stop(t); catch, end
                try delete(t); catch, end
            end
            setappdata(f,'liveTimer',[]);

            % MCC error handling: no dialogs
            try cbErrHandling(0,0); catch, end

            boardNum = getappdata(f,'boardNum');
            gain     = getappdata(f,'gain');

            ch1 = get(getappdata(f,'popupDev1'),'Value') - 1; % AI#
            ch2 = get(getappdata(f,'popupDev2'),'Value') - 1; % AI#
            setappdata(f,'chanNum1',ch1);
            setappdata(f,'chanNum2',ch2);

            % Ping reads to validate
            [err1, ~] = cbAIn(boardNum, ch1, gain);
            [err2, ~] = cbAIn(boardNum, ch2, gain);
            if err1 ~= 0 || err2 ~= 0
                error('MCC cbAIn error (err1=%d, err2=%d).', err1, err2);
            end

            set(statusTxt,'String',sprintf('Digilent/MCC connecté (USB-1208FS-PLUS) | canaux [AI%d, AI%d]',ch1,ch2), ...
                          'ForegroundColor','green');

        catch ME
            set(statusTxt,'String','Échec de connexion Digilent/MCC','ForegroundColor','red');
            disp(getReport(ME,'extended'));
        end
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

    ch1 = getappdata(fig,'chanNum1');
    ch2 = getappdata(fig,'chanNum2');
    if isempty(ch1) || isempty(ch2)
        set(statusTxt,'String','Canaux MCC non définis. (Re)connectez.','ForegroundColor','red');
        return
    end

    windowPts = Fs * 5;   % show last 5 s
    chunkPts  = 200;      % ~0.1 s at 2kHz

    if src.Value
        % --- START ---
        setappdata(fig,'rawBuf',[]);
        setappdata(fig,'sampleIdx',0);
        src.String = 'Arrêter l''enregistrement';

        cla(ax_raw1); hold(ax_raw1,'on'); title(ax_raw1,'EMG1 brut');
        cla(ax_raw2); hold(ax_raw2,'on'); title(ax_raw2,'EMG2 brut');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)');

        hLine1 = plot(ax_raw1,nan,nan,'-'); setappdata(fig,'hLine_raw1',hLine1);
        hLine2 = plot(ax_raw2,nan,nan,'-'); setappdata(fig,'hLine_raw2',hLine2);

        set(ax_raw1,'XLim',[0, windowPts]);
        set(ax_raw2,'XLim',[0, windowPts]);

        % Timer acquisition (reads each channel separately => no "contiguous channels" constraint)
        t = timer('ExecutionMode','fixedSpacing', ...
                  'Period', chunkPts/Fs, ...
                  'TimerFcn', @processLiveTick, ...
                  'ErrorFcn',  @onTimerError);
        setappdata(fig,'liveTimer',t);
        start(t);

    else
        % --- STOP ---
        src.String = 'Commencer l''enregistrement';

        t = getappdata(fig,'liveTimer');
        if ~isempty(t) && isa(t,'timer') && isvalid(t)
            try stop(t); catch, end
            try delete(t); catch, end
        end
        setappdata(fig,'liveTimer',[]);

        rawBuf = getappdata(fig,'rawBuf');

        if ~isempty(rawBuf)
            ch1sig = rawBuf(:,1);
            ch2sig = rawBuf(:,2);

            filt1 = filterEMG(ch1sig);
            filt2 = filterEMG(ch2sig);

            mvc = getappdata(fig,'mvc_values');
            if ~isempty(mvc)
                if numel(mvc)>=1 && mvc(1)>0, filt1 = filt1 / mvc(1); end
                if numel(mvc)>=2 && mvc(2)>0, filt2 = filt2 / mvc(2); end
            end

            cla(ax_filt1); plot(ax_filt1,filt1);
            title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Échantillon'); ylabel(ax_filt1,'Amplitude');

            cla(ax_filt2); plot(ax_filt2,filt2);
            title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Échantillon'); ylabel(ax_filt2,'Amplitude');

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

        % Acquire chunkPts samples for CH1
        v1 = acquireOneChannel(boardNum, ch1, gain, Fs, chunkPts);

        % Acquire chunkPts samples for CH2
        v2 = acquireOneChannel(boardNum, ch2, gain, Fs, chunkPts);

        volts = [v1(:), v2(:)];

        rawBuf = [rawBuf; volts]; %#ok<AGROW>
        setappdata(fig,'rawBuf',rawBuf);

        N = size(volts,1);
        sampleIdx = sampleIdx + N;
        setappdata(fig,'sampleIdx',sampleIdx);

        if sampleIdx <= windowPts
            idx = 1:sampleIdx;
        else
            idx = (sampleIdx-windowPts+1):sampleIdx;
        end

        ch1win = rawBuf(idx,1);
        ch2win = rawBuf(idx,2);

        active1 = (std(double(ch1win)) > 1e-6) || (max(abs(ch1win)) > 1e-5);
        active2 = (std(double(ch2win)) > 1e-6) || (max(abs(ch2win)) > 1e-5);

        if active1
            set(hLine1,'XData',idx,'YData',ch1win);
            set(ax_raw1,'XLim',[max(1,sampleIdx-windowPts+1), sampleIdx]);
        else
            set(hLine1,'XData',nan,'YData',nan);
        end

        if active2
            set(hLine2,'XData',idx,'YData',ch2win);
            set(ax_raw2,'XLim',[max(1,sampleIdx-windowPts+1), sampleIdx]);
        else
            set(hLine2,'XData',nan,'YData',nan);
        end

        drawnow limitrate;
    end

    function onTimerError(~,evt)
        set(statusTxt,'String','Erreur acquisition Digilent/MCC (timer).','ForegroundColor','red');
        disp(evt.Data);
    end
end

function v = acquireOneChannel(boardNum, physCh, gain, Fs, nPts)
    % Acquire one channel using cbAInScan (blocking), return volts (exact if cbToEngUnits exists).
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

        % Exact conversion if available
        if exist('cbToEngUnits','file') == 2
            v = zeros(size(rawCounts));
            for i = 1:numel(rawCounts)
                [err2, eng] = cbToEngUnits(boardNum, gain, rawCounts(i));
                if err2 ~= 0
                    % fallback approximate
                    v(i) = (rawCounts(i) - 2048) / 2048 * 10;
                else
                    v(i) = eng;
                end
            end
        else
            % Approx conversion for 12-bit bipolar ±10V
            v = (rawCounts - 2048) / 2048 * 10;
        end

    catch ME
        try cbWinBufFree(memHandle); catch, end
        rethrow(ME);
    end
end

function measureMVC(figHandle,mvcTxt,chIdx)
    % Measure MVC for a SINGLE selected channel (5 s). Blocking acquisition then plots.

    boardNum = getappdata(figHandle,'boardNum');
    gain     = getappdata(figHandle,'gain');
    Fs       = getappdata(figHandle,'Fs');

    % Stop any live timer
    t = getappdata(figHandle,'liveTimer');
    if ~isempty(t) && isa(t,'timer') && isvalid(t)
        try stop(t); catch, end
        try delete(t); catch, end
    end
    setappdata(figHandle,'liveTimer',[]);

    ch1 = getappdata(figHandle,'chanNum1'); if isempty(ch1), ch1 = 0; end
    ch2 = getappdata(figHandle,'chanNum2'); if isempty(ch2), ch2 = 1; end

    ax_raw1  = getappdata(figHandle,'ax_raw1');
    ax_raw2  = getappdata(figHandle,'ax_raw2');
    ax_filt1 = getappdata(figHandle,'ax_filt1');
    ax_filt2 = getappdata(figHandle,'ax_filt2');

    mvc = getappdata(figHandle,'mvc_values'); if isempty(mvc), mvc = [0 0]; end
    if mvc(chIdx) > 0
        cla(ax_raw1);  title(ax_raw1,'EMG1 brut');  xlabel(ax_raw1,'Échantillon'); ylabel(ax_raw1,'Amplitude'); hold(ax_raw1,'on');
        cla(ax_raw2);  title(ax_raw2,'EMG2 brut');  xlabel(ax_raw2,'Échantillon'); ylabel(ax_raw2,'Amplitude'); hold(ax_raw2,'on');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Échantillon'); ylabel(ax_filt1,'Amplitude'); hold(ax_filt1,'on');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Échantillon'); ylabel(ax_filt2,'Amplitude'); hold(ax_filt2,'on');
        setappdata(figHandle,'mvc_waveforms',struct('raw1',[],'raw2',[],'env1',[],'env2',[]));
    end

    if chIdx==1
        targetRaw = ax_raw1; targetFilt = ax_filt1; physCh = ch1; side = 1;
    else
        targetRaw = ax_raw2; targetFilt = ax_filt2; physCh = ch2; side = 2;
    end

    durSec = 5;
    nPts   = Fs * durSec;

    set(mvcTxt,'String',sprintf('Mesure MVC%d en cours (5 s)...',side)); drawnow;

    buf = acquireOneChannel(boardNum, physCh, gain, Fs, nPts);

    cla(targetRaw);  hold(targetRaw,'on');
    cla(targetFilt); hold(targetFilt,'on');
    title(targetRaw, sprintf('EMG%d MVC (%ds)', side, durSec));
    xlabel(targetRaw,'Échantillon'); ylabel(targetRaw,'Amplitude');
    title(targetFilt, sprintf('EMG%d enveloppe MVC', side));
    xlabel(targetFilt,'Échantillon'); ylabel(targetFilt,'Amplitude');

    plot(targetRaw, buf, '-');

    envFull = sqrt(movmean((buf - mean(buf)).^2, 100));
    plot(targetFilt, envFull, '-');

    nTake = min(2000, numel(buf));
    topVals = maxk(abs(buf), nTake);
    mvcVal = median(topVals);

    mvcLoc = getappdata(figHandle,'mvc_values'); if isempty(mvcLoc), mvcLoc = [0 0]; end
    mvcLoc(side) = mvcVal;
    setappdata(figHandle,'mvc_values', mvcLoc);

    wf = getappdata(figHandle,'mvc_waveforms');
    if side==1
        wf.raw1 = buf;  wf.env1 = envFull;
    else
        wf.raw2 = buf;  wf.env2 = envFull;
    end
    setappdata(figHandle,'mvc_waveforms',wf);

    set(mvcTxt,'String',sprintf('MVC1 = %.2f | MVC2 = %.2f',mvcLoc(1),mvcLoc(2)));

    reconnectLive(figHandle);
end

function reconnectLive(figHandle)
    connectFcn = getappdata(figHandle,'connectFcn');
    if isa(connectFcn,'function_handle')
        try connectFcn(); catch, end
    end
end

function filtered = filterEMG(raw)
    raw = raw - mean(raw);

    Fs = 2000;
    f0 = 60;
    Q = 2;
    wo = f0/(Fs/2); bw = wo/Q;

    [b,a] = designNotchPeakIIR('Response','notch','CenterFrequency',f0, ...
        'QualityFactor',Q,'SampleRate',Fs);
    emg_notch = filtfilt(b,a, raw);

    [b,a] = butter(4, [20 400]/(Fs/2), 'bandpass');
    emg = filtfilt(b,a,emg_notch);
    filtered = sqrt(movmean(emg.^2,100));
end

function exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2)
    fig = figure('Visible','off','Position',[100,100,1200,800]);
    subplot(2,2,1);
    copyobj(allchild(ax_raw1), gca);
    title('EMG1 brut'); xlabel('Échantillon'); ylabel('Amplitude');

    subplot(2,2,2);
    copyobj(allchild(ax_raw2), gca);
    title('EMG2 brut'); xlabel('Échantillon'); ylabel('Amplitude');

    subplot(2,2,3);
    copyobj(allchild(ax_filt1), gca);
    title('EMG1 filtré (normalisé)'); xlabel('Échantillon'); ylabel('Amplitude');

    subplot(2,2,4);
    copyobj(allchild(ax_filt2), gca);
    title('EMG2 filtré (normalisé)'); xlabel('Échantillon'); ylabel('Amplitude');

    [file,path] = uiputfile('*.png','Exporter les graphiques sous...');
    if ~isequal(file,0)
        saveas(fig, fullfile(path,file));
        disp(['Graphiques exportés vers : ', fullfile(path,file)]);
    else
        disp('Exportation annulée.');
    end
    close(fig);
end
