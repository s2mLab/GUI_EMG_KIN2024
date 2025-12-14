function EMG_GUI_digilent()
    % NI DAQ EMG GUI for real-time data acquisition and display (2 channels)

    % Create the GUI
    f = figure('Name','NI DAQ EMG Acquisition','NumberTitle','off', ...
               'Position',[100,100,900,700],'Units','normalized');

    %% Status & MVC text
    statusTxt = uicontrol(f,'Style','text','String','Connexion à NI DAQ...', ...
        'Units','normalized','Position',[0.05,0.94,0.5,0.04], ...
        'FontSize',12,'HorizontalAlignment','left');
    mvcTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.58,0.94,0.4,0.04], ...
        'FontSize',12,'HorizontalAlignment','left','ForegroundColor',[0 0 0]);

    %% Channel choosers (act as "spot" selectors) + (Re)connect
    devList = arrayfun(@(k) sprintf('Dev%d',k), 1:9, 'UniformOutput', false); % labels kept
    uicontrol(f,'Style','text','String','EMG1 canal:', ...
        'Units','normalized','Position',[0.05,0.905,0.08,0.035],'HorizontalAlignment','left');
    popupDev1 = uicontrol(f,'Style','popupmenu','String',devList, ...
        'Units','normalized','Position',[0.13,0.9,0.08,0.045], 'FontSize',11);

    uicontrol(f,'Style','text','String','EMG2 canal:', ...
        'Units','normalized','Position',[0.22,0.905,0.08,0.035],'HorizontalAlignment','left');
    popupDev2 = uicontrol(f,'Style','popupmenu','String',devList, ...
        'Units','normalized','Position',[0.30,0.9,0.08,0.045], 'FontSize',11, 'Value',2);

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

    % Independent MVC buttons (MVC1 / MVC2)
    uicontrol(f,'Style','pushbutton','String','MVC 1', ...
        'Units','normalized','Position',[0.76,0.9,0.08,0.05],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,1));
    uicontrol(f,'Style','pushbutton','String','MVC 2', ...
        'Units','normalized','Position',[0.85,0.9,0.08,0.05],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,2));

    uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
        'Units','normalized','Position',[0.83,0.84,0.15,0.05],'FontSize',12, ...
        'Callback',@(~,~) exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2));

    %% Detect an NI device once; channel(s) are chosen from popups
    try
        daqreset();
        devs = daq.getDevices();
        if ~isempty(devs)
            deviceID = char(devs(1).ID);   % e.g., 'Dev1' or 'cDAQ1Mod1'
        else
            deviceID = 'Dev1';             % fallback
        end
    catch
        deviceID = 'Dev1';
    end

    % Store shared items
    setappdata(f,'deviceID',deviceID);
    setappdata(f,'popupDev1',popupDev1);
    setappdata(f,'popupDev2',popupDev2);

    setappdata(f,'ax_raw1',ax_raw1);
    setappdata(f,'ax_raw2',ax_raw2);
    setappdata(f,'ax_filt1',ax_filt1);
    setappdata(f,'ax_filt2',ax_filt2);
    setappdata(f,'hLine_raw1',hLine_raw1);
    setappdata(f,'hLine_raw2',hLine_raw2);

    % Store MVC values vector [mvc1 mvc2]; start empty (0 means not set)
    setappdata(f,'mvc_values',[0 0]);

    % Optional store of MVC waveforms for persistence on screen
    setappdata(f,'mvc_waveforms',struct('raw1',[],'raw2',[],'env1',[],'env2',[]));

    % Recording counter & store
    setappdata(f,'rec_count',0);
    setappdata(f,'recordings_raw',{}); % cell per recording

    connectDAQ();  % initial connection using current popup selections

    % Expose the reconnect function to outside (for MVC to rebuild dLive)
    setappdata(f,'connectFcn', @connectDAQ);

    %% Nested function: (Re)connect using current popup selections as CHANNELS
    function connectDAQ()
        try
            % Clean up any previous live session
            oldLive = getappdata(f,'dLive');
            if ~isempty(oldLive) && isvalid(oldLive)
                try stop(oldLive); catch, end
                try release(oldLive); catch, end
            end

            daqreset();
            deviceID = getappdata(f,'deviceID');
            ch1 = get(getappdata(f,'popupDev1'),'Value');  % 1..9
            ch2 = get(getappdata(f,'popupDev2'),'Value');  % 1..9
            setappdata(f,'chanNum1',ch1);
            setappdata(f,'chanNum2',ch2);

            dLive = daq.createSession('ni');
            dLive.Rate = 2000;

            % Try 1-based channels first, then 0-based fallback (covers NI variants)
            try
                dLive.addAnalogInputChannel(deviceID, ch1, 'Voltage');
            catch
                dLive.addAnalogInputChannel(deviceID, ch1-1, 'Voltage');
            end
            try
                dLive.addAnalogInputChannel(deviceID, ch2, 'Voltage');
            catch
                dLive.addAnalogInputChannel(deviceID, ch2-1, 'Voltage');
            end

            % Terminal config
            for k=1:numel(dLive.Channels)
                dLive.Channels(k).TerminalConfig = 'SingleEnded';
            end
            dLive.IsContinuous = true;

            setappdata(f,'dLive',dLive);
            set(statusTxt,'String',sprintf('NI DAQ connecté : %s | canaux [%d, %d]',deviceID,ch1,ch2), ...
                          'ForegroundColor','green');

        catch ME
            set(statusTxt,'String','Échec de connexion NI DAQ','ForegroundColor','red');
            disp(getReport(ME,'extended'));
        end
    end
end

function startStopDAQ(src,statusTxt)
    % Toggle live acquisition; stores ALL data for both channels
    persistent lh rawBuf sampleIdx
    fig = ancestor(src,'figure');

    % Re-fetch current objects from appdata
    dLive     = getappdata(fig,'dLive');
    ax_raw1   = getappdata(fig,'ax_raw1');
    ax_raw2   = getappdata(fig,'ax_raw2');
    ax_filt1  = getappdata(fig,'ax_filt1');
    ax_filt2  = getappdata(fig,'ax_filt2');
    hLine1    = getappdata(fig,'hLine_raw1');
    hLine2    = getappdata(fig,'hLine_raw2');

    if isempty(dLive) || ~isvalid(dLive)
        set(statusTxt,'String','Session NI invalide. (Re)connectez.','ForegroundColor','red');
        return
    end
    windowPts = dLive.Rate * 5;  % show last 5 s

    if src.Value
        % --- START ---
        rawBuf    = [];
        sampleIdx = 0;
        src.String = 'Arrêter l''enregistrement';

        % Clear ALL four panes before recording (as requested)
        cla(ax_raw1); hold(ax_raw1,'on'); title(ax_raw1,'EMG1 brut');
        cla(ax_raw2); hold(ax_raw2,'on'); title(ax_raw2,'EMG2 brut');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)');

        % Recreate live line handles (since we cleared)
        hLine1 = plot(ax_raw1,nan,nan,'-'); setappdata(fig,'hLine_raw1',hLine1);
        hLine2 = plot(ax_raw2,nan,nan,'-'); setappdata(fig,'hLine_raw2',hLine2);

        dLive.NotifyWhenDataAvailableExceeds = 200;
        if ~isempty(lh) && isvalid(lh), delete(lh); end
        lh = dLive.addlistener('DataAvailable', @(~,evt) processLive(evt));

        % Prepare raw axes limits
        set(ax_raw1,'XLim',[0, windowPts]);
        set(ax_raw2,'XLim',[0, windowPts]);

        dLive.startBackground();
    else
        % --- STOP ---
        src.String = 'Commencer l''enregistrement';
        try stop(dLive); catch, end
        if ~isempty(lh) && isvalid(lh), delete(lh); end

        % Final filtered + normalized plots for both channels
        if ~isempty(rawBuf)
            ch1 = rawBuf(:,1);
            ch2 = rawBuf(:,min(2,size(rawBuf,2))); % safe if only one channel for any reason

            filt1 = filterEMG(ch1);
            filt2 = filterEMG(ch2);

            mvc = getappdata(fig,'mvc_values'); % [mvc1 mvc2]
            if ~isempty(mvc)
                if numel(mvc)>=1 && mvc(1)>0, filt1 = filt1 / mvc(1); end
                if numel(mvc)>=2 && mvc(2)>0, filt2 = filt2 / mvc(2); end
            end

            cla(ax_filt1); plot(ax_filt1,filt1);
            title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Échantillon'); ylabel(ax_filt1,'Amplitude');

            cla(ax_filt2); plot(ax_filt2,filt2);
            title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Échantillon'); ylabel(ax_filt2,'Amplitude');

            % Save accumulative recordings with incremental IDs
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

            % Also keep most recent under fixed names
            assignin('base','EMG_data_raw', rawBuf);
            assignin('base','EMG1_filtered', filt1);
            assignin('base','EMG2_filtered', filt2);

            disp(['Enregistrement #',num2str(rec_count),' sauvegardé (variables : ', ...
                  baseRawVar,', ',baseF1Var,', ',baseF2Var,').']);
        else
            disp('Aucune donnée enregistrée.');
        end
    end

    function processLive(evt)
        % Scroll a sliding window but keep rawBuf unlimited
        newData = evt.Data;
        if size(newData,2)==1
            % Ensure 2 columns for consistent handling
            newData = [newData, newData*0];
        end

        % Buffer
        rawBuf  = [rawBuf; newData];
        N = size(newData,1);
        sampleIdx = sampleIdx + N;

        if sampleIdx <= windowPts
            idx = 1:sampleIdx;
        else
            idx = (sampleIdx-windowPts+1):sampleIdx;
        end

        % Activity detection per channel
        ch1 = rawBuf(idx,1);
        ch2 = rawBuf(idx,2);
        active1 = (std(double(ch1)) > 1e-6) || (max(abs(ch1)) > 1e-5);
        active2 = (std(double(ch2)) > 1e-6) || (max(abs(ch2)) > 1e-5);

        if active1
            set(hLine1,'XData',idx,'YData',ch1);
            set(ax_raw1,'XLim',[max(1,sampleIdx-windowPts+1), sampleIdx]);
        else
            set(hLine1,'XData',nan,'YData',nan);
        end

        if active2
            set(hLine2,'XData',idx,'YData',ch2);
            set(ax_raw2,'XLim',[max(1,sampleIdx-windowPts+1), sampleIdx]);
        else
            set(hLine2,'XData',nan,'YData',nan);
        end

        drawnow limitrate;
    end
end

function measureMVC(figHandle,mvcTxt,chIdx)
    % Measure MVC for a SINGLE selected channel (5 s) with LIVE display.

    % If live session is running, stop and RELEASE it
    dLive = getappdata(figHandle,'dLive');
    if ~isempty(dLive) && isvalid(dLive)
        try stop(dLive); catch, end
        try release(dLive); catch, end
    end
    setappdata(figHandle,'dLive',[]);  % mark as detached

    % Ensure device is free, then set up a clean session
    try daqreset(); catch, end

    deviceID = getappdata(figHandle,'deviceID'); if isempty(deviceID), deviceID = 'Dev1'; end
    ch1 = getappdata(figHandle,'chanNum1'); if isempty(ch1), ch1 = 1; end
    ch2 = getappdata(figHandle,'chanNum2'); if isempty(ch2), ch2 = 2; end

    % Axes
    ax_raw1  = getappdata(figHandle,'ax_raw1');
    ax_raw2  = getappdata(figHandle,'ax_raw2');
    ax_filt1 = getappdata(figHandle,'ax_filt1');
    ax_filt2 = getappdata(figHandle,'ax_filt2');

    % If redoing on that side, clear panes for clarity (keeps other side if not redone)
    mvc = getappdata(figHandle,'mvc_values'); if isempty(mvc), mvc = [0 0]; end
    if mvc(chIdx) > 0
        cla(ax_raw1);  title(ax_raw1,'EMG1 brut');  xlabel(ax_raw1,'Échantillon'); ylabel(ax_raw1,'Amplitude'); hold(ax_raw1,'on');
        cla(ax_raw2);  title(ax_raw2,'EMG2 brut');  xlabel(ax_raw2,'Échantillon'); ylabel(ax_raw2,'Amplitude'); hold(ax_raw2,'on');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Échantillon'); ylabel(ax_filt1,'Amplitude'); hold(ax_filt1,'on');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Échantillon'); ylabel(ax_filt2,'Amplitude'); hold(ax_filt2,'on');
        setappdata(figHandle,'mvc_waveforms',struct('raw1',[],'raw2',[],'env1',[],'env2',[]));
    end

    % Decide which physical channel to sample
    if chIdx==1
        targetRaw = ax_raw1; targetFilt = ax_filt1; physCh = ch1; side = 1;
    else
        targetRaw = ax_raw2; targetFilt = ax_filt2; physCh = ch2; side = 2;
    end

    % --- LIVE streaming for 5 seconds with listener + timer ---
    Fs = 2000; durSec = 5;
    sMVC = [];
    try
        sMVC = daq.createSession('ni');
        sMVC.Rate = Fs;
        sMVC.IsContinuous = true;
        try
            sMVC.addAnalogInputChannel(deviceID, physCh, 'Voltage');
        catch
            sMVC.addAnalogInputChannel(deviceID, physCh-1, 'Voltage');
        end
        sMVC.Channels(1).TerminalConfig = 'SingleEnded';
    catch ME
        set(mvcTxt,'String',sprintf('MVC%d non mesuré (erreur matériel).',side));
        if ~isempty(sMVC), try release(sMVC); catch, end, end
        reconnectLive(figHandle);
        disp(getReport(ME,'extended'));
        return
    end

    % Prepare axes for live display
    cla(targetRaw);  hold(targetRaw,'on');
    cla(targetFilt); hold(targetFilt,'on');
    title(targetRaw, sprintf('EMG%d MVC (LIVE, %ds)', side));
    xlabel(targetRaw,'Échantillon'); ylabel(targetRaw,'Amplitude');
    title(targetFilt, sprintf('EMG%d enveloppe MVC (LIVE)', side));
    xlabel(targetFilt,'Échantillon'); ylabel(targetFilt,'Amplitude');
    set(targetRaw,'XLim',[0 Fs*durSec]);

    hRaw  = plot(targetRaw,nan,nan,'-');
    hFilt = plot(targetFilt,nan,nan,'-');

    set(mvcTxt,'String',sprintf('Mesure MVC%d en cours (5 s)...',side)); drawnow;

    % Live buffers and listener
    buf = [];
    sMVC.NotifyWhenDataAvailableExceeds = 200;
    lh = sMVC.addlistener('DataAvailable', @(~,evt) onData(evt));

    % Timer to stop after 5 seconds
    t = timer('StartDelay',durSec,'TimerFcn',@(~,~) stopAndFinalize());
    start(t);
    try
        sMVC.startBackground();
    catch ME
        set(mvcTxt,'String',sprintf('MVC%d non mesuré (erreur démarrage).',side));
        try delete(lh); catch, end
        try stop(sMVC); catch, end
        try release(sMVC); catch, end
        stopTimerSafe(t);
        reconnectLive(figHandle);
        disp(getReport(ME,'extended'));
        return
    end

    % ------- nested helpers (capture workspace of measureMVC) -------
    function onData(evt)
        newy = evt.Data(:,1);
        buf  = [buf; newy]; %#ok<AGROW>

        % Live raw
        x = 1:numel(buf);
        set(hRaw,'XData',x,'YData',buf);

        % Live envelope (quick RMS window)
        env = sqrt(movmean((buf - mean(buf)).^2, 100));
        set(hFilt,'XData',x,'YData',env);

        drawnow limitrate;
    end

    function stopAndFinalize()
        % Stop + cleanup session
        try stop(sMVC); catch, end
        try delete(lh); catch, end
        try release(sMVC); catch, end
        stopTimerSafe(t);

        if isempty(buf) || all(~isfinite(buf))
            set(mvcTxt,'String',sprintf('MVC%d non mesuré (pas de signal).',side));
            reconnectLive(figHandle);
            return
        end

        % Compute MVC = median of top 2000 abs samples (or all if shorter)
        nTake = min(2000, numel(buf));
        topVals = maxk(abs(buf), nTake);
        mvcVal = median(topVals);

        % Save MVC values
        mvcLoc = getappdata(figHandle,'mvc_values'); if isempty(mvcLoc), mvcLoc = [0 0]; end
        mvcLoc(side) = mvcVal;
        setappdata(figHandle,'mvc_values', mvcLoc);

        % Persist final waveforms on screen (already plotted) + store
        envFull = sqrt(movmean((buf - mean(buf)).^2, 100));
        wf = getappdata(figHandle,'mvc_waveforms');
        if side==1
            wf.raw1 = buf;  wf.env1 = envFull;
        else
            wf.raw2 = buf;  wf.env2 = envFull;
        end
        setappdata(figHandle,'mvc_waveforms',wf);

        set(mvcTxt,'String',sprintf('MVC1 = %.2f | MVC2 = %.2f',mvcLoc(1),mvcLoc(2)));

        % Reconnect the live session (so Start Recording works immediately)
        reconnectLive(figHandle);
    end

    function stopTimerSafe(tt)
        if isa(tt,'timer') && isvalid(tt)
            try stop(tt); catch, end
            try delete(tt); catch, end
        end
    end
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
    Q = 2;                % Q=35–60: notch fin
    wo = f0/(Fs/2); bw = wo/Q;
    [b,a] = iirnotch(wo, bw);
    emg_notch = filtfilt(b,a, raw);         % zero-phase
        
    
    [b,a] = butter(4, [20 400]/(Fs/2), 'bandpass'); % Fs = 2000 -> Nyquist = 1000
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