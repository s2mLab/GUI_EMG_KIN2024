function EMG_GUI_digilent()
% EMG GUI — Digilent/MCC (USB-1208FS-PLUS) OR TEST MODE (no hardware)
%
% Refactor goals:
% - Reduce duplicated code (axes reset, plotting, UI state, acquisition loops)
% - Improve robustness (clean stop on errors, safe close, consistent UI state)
% - Consistent test-mode streaming for RECORD + MVC using chunking + pause pacing
%
% Hardware mode:
%   - Requires MCC Universal Library for MATLAB (cbAIn, cbAInScan, cbWinBufAlloc, ...)
%   - Reads a pair of AI channels (AI0-1, AI1-2, ..., AI6-7)
%
% Test mode:
%   - Streams simulated data in real time
%   - Simulated signals have mean ~0; amplitude changes; one muscle has 60 Hz interference

    f = figure('Name','EMG Acquisition','NumberTitle','off', ...
        'Position',[100,100,900,700],'Units','normalized', ...
        'CloseRequestFcn', @onClose);

    %% Colours & constants
    color_emg1 = [0 0.4470 0.7410];
    color_emg2 = [0.8500 0.3250 0.0980];
    alpha_overlay = 0.20;

    Fs = 2000;
    boardNum = 0;

    %% Store constants/state
    setappdata(f,'color_emg1',color_emg1);
    setappdata(f,'color_emg2',color_emg2);
    setappdata(f,'alpha_overlay',alpha_overlay);

    setappdata(f,'Fs',Fs);
    setappdata(f,'boardNum',boardNum);

    setappdata(f,'gain',getDefaultGain());

    setappdata(f,'mvc_values',[0 0]);
    setappdata(f,'rec_count',0);
    setappdata(f,'recordings_raw',{});
    setappdata(f,'rawBuf',[]);
    setappdata(f,'sampleIdx',0);
    setappdata(f,'test_mode',false);
    setappdata(f,'isRecording',false);

    setappdata(f,'sim_data',[]);
    setappdata(f,'sim_idx_record',1);  % index for record
    setappdata(f,'sim_idx_mvc',1);     % index for MVC (separate!)
    setappdata(f,'recBlinkOn',false);

    %% Build UI
    buildUI();

    %% Initial connect
    connectDAQ();

    % ============================
    % UI BUILD
    % ============================
    function buildUI()
        % Status + MVC + REC
        statusTxt = uicontrol(f,'Style','text','String','Prêt. Activez 🧪 Test si pas de carte.', ...
            'Units','normalized','Position',[0.05,0.94,0.60,0.04], ...
            'FontSize',12,'HorizontalAlignment','left');
        setappdata(f,'statusTxt',statusTxt);

        recTxt = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.40,0.94,0.15,0.04], ...
            'FontSize',12,'FontWeight','bold','HorizontalAlignment','left', ...
            'ForegroundColor',[1 0 0]);
        setappdata(f,'recTxt',recTxt);

        mvcTxt = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.58,0.94,0.4,0.04], ...
            'FontSize',12,'HorizontalAlignment','left');
        setappdata(f,'mvcTxt',mvcTxt);

        % Popup pair
        pairList = arrayfun(@(k) sprintf('AI%d-%d',k,k+1), 0:6, 'UniformOutput', false);
        uicontrol(f,'Style','text','String','Paire EMG:', ...
            'Units','normalized','Position',[0.05,0.905,0.08,0.035],'HorizontalAlignment','left');

        popupPair = uicontrol(f,'Style','popupmenu','String',pairList, ...
            'Units','normalized','Position',[0.13,0.905,0.10,0.035], ...
            'FontSize',11,'Value',1, ...
            'Callback',@(~,~) connectDAQ());
        setappdata(f,'popupPair',popupPair);

        % Axes
        ax_raw1  = axes(f,'Units','normalized','Position',[0.07,0.53,0.40,0.30]); hold(ax_raw1,'on');
        ax_raw2  = axes(f,'Units','normalized','Position',[0.53,0.53,0.40,0.30]); hold(ax_raw2,'on');
        ax_filt1 = axes(f,'Units','normalized','Position',[0.07,0.10,0.40,0.30]); hold(ax_filt1,'on');
        ax_filt2 = axes(f,'Units','normalized','Position',[0.53,0.10,0.40,0.30]); hold(ax_filt2,'on');

        setappdata(f,'ax_raw1',ax_raw1);
        setappdata(f,'ax_raw2',ax_raw2);
        setappdata(f,'ax_filt1',ax_filt1);
        setappdata(f,'ax_filt2',ax_filt2);

        % Live line handles (raw only)
        hLine_raw1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1);
        hLine_raw2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2);
        setappdata(f,'hLine_raw1',hLine_raw1);
        setappdata(f,'hLine_raw2',hLine_raw2);

        % Buttons (top row)
        btnTest = uicontrol(f,'Style','togglebutton','String','🧪 Test', ...
            'Units','normalized','Position',[0.46,0.905,0.07,0.035],'FontSize',11, ...
            'Callback',@(src,~) toggleTestMode(src));
        setappdata(f,'btnTest',btnTest);

        btnStart = uicontrol(f,'Style','togglebutton','String','⏺ Enregistrer', ...
            'Units','normalized','Position',[0.54,0.905,0.20,0.035],'FontSize',12, ...
            'Callback',@(src,~) startStopDAQ(src));
        setappdata(f,'btnStart',btnStart);

        uicontrol(f,'Style','pushbutton','String','MVC 1', ...
            'Units','normalized','Position',[0.76,0.905,0.08,0.035],'FontSize',12, ...
            'Callback',@(~,~) measureMVC(1));

        uicontrol(f,'Style','pushbutton','String','MVC 2', ...
            'Units','normalized','Position',[0.85,0.905,0.08,0.035],'FontSize',12, ...
            'Callback',@(~,~) measureMVC(2));

        % Bottom buttons
        uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
            'Units','normalized','Position',[0.60,0.02,0.18,0.035],'FontSize',12, ...
            'Callback',@(~,~) exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2));

        uicontrol(f,'Style','pushbutton','String','Exporter CSV', ...
            'Units','normalized','Position',[0.80,0.02,0.18,0.035],'FontSize',12, ...
            'Callback',@(~,~) exportCSV(f));

        % Initial axes labels/titles
        resetAllAxes('idle');
    end

    % ============================
    % UI STATE HELPERS
    % ============================
    function setStatus(msg, colorNameOrRGB)
        figHandle = f; % stable
        statusTxt = getappdata(figHandle,'statusTxt');
        if isempty(statusTxt) || ~isvalid(statusTxt), return, end
        set(statusTxt,'String',msg);
        if nargin>=2
            set(statusTxt,'ForegroundColor',colorNameOrRGB);
        end
    end

    function setUIState(state)
        figHandle = f;
        popupPair = getappdata(figHandle,'popupPair');
        btnStart  = getappdata(figHandle,'btnStart');
        recTxt    = getappdata(figHandle,'recTxt');

        if isempty(popupPair) || ~isvalid(popupPair), return, end

        switch state
            case 'idle'
                set(popupPair,'Enable','on');
                if ~isempty(btnStart) && isvalid(btnStart)
                    btnStart.Value = 0;
                    btnStart.String = '⏺ Enregistrer';
                end
                if ~isempty(recTxt) && isvalid(recTxt)
                    set(recTxt,'String','');
                end
                setappdata(figHandle,'recBlinkOn',false);

            case 'recording'
                set(popupPair,'Enable','off');
                if ~isempty(btnStart) && isvalid(btnStart)
                    btnStart.String = '⏹ Stop';
                end
                if ~isempty(recTxt) && isvalid(recTxt)
                    set(recTxt,'String','REC ●');
                end
                setappdata(figHandle,'recBlinkOn',true);

            case 'mvc'
                set(popupPair,'Enable','off');
        end
    end

    function resetAllAxes(context)
        figHandle = f;
        ax_raw1  = getappdata(figHandle,'ax_raw1');
        ax_raw2  = getappdata(figHandle,'ax_raw2');
        ax_filt1 = getappdata(figHandle,'ax_filt1');
        ax_filt2 = getappdata(figHandle,'ax_filt2');

        cla(ax_raw1);  hold(ax_raw1,'on');
        cla(ax_raw2);  hold(ax_raw2,'on');
        cla(ax_filt1); hold(ax_filt1,'on');
        cla(ax_filt2); hold(ax_filt2,'on');

        applyAxisStyle(ax_raw1,  'EMG1 brut', color_emg1, 'Activité (V)');
        applyAxisStyle(ax_raw2,  'EMG2 brut', color_emg2, 'Activité (V)');
        applyAxisStyle(ax_filt1, 'EMG1 filtré (normalisé)', color_emg1, '(%MVC)');
        applyAxisStyle(ax_filt2, 'EMG2 filtré (normalisé)', color_emg2, '(%MVC)');

        % Recreate live line handles after clearing
        hLine_raw1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1);
        hLine_raw2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2);
        setappdata(figHandle,'hLine_raw1',hLine_raw1);
        setappdata(figHandle,'hLine_raw2',hLine_raw2);

        if any(strcmp(context, {'recording','mvc'}))
            set(ax_raw1,'XLim',[0 5]);
            set(ax_raw2,'XLim',[0 5]);
            set(ax_filt1,'XLim',[0 5]);
            set(ax_filt2,'XLim',[0 5]);
        end
    end

    function applyAxisStyle(ax, titleStr, titleColor, yLabelStr)
        t = title(ax,titleStr);
        set(t,'Color',titleColor);
        xlabel(ax,'Temps (s)');
        ylabel(ax,yLabelStr);
    end

    % ============================
    % CONNECT / TEST MODE
    % ============================
    function connectDAQ()
        figHandle = f;
        [ch1, ch2] = getSelectedPair();
        setappdata(figHandle,'chanNum1',ch1);
        setappdata(figHandle,'chanNum2',ch2);

        if getappdata(figHandle,'test_mode')
            setStatus(sprintf('Mode TEST (simulé) | paire AI%d-%d',ch1,ch2), [0.2 0.2 0.2]);
            return
        end

        if ~(exist('cbAIn','file')==2 || exist('cbAIn','file')==3)
            setStatus('MCC UL introuvable (cbAIn). Activez 🧪 Test ou installez MCC UL.', 'red');
            return
        end

        try
            try cbErrHandling(0,0); catch, end
            bn = getappdata(figHandle,'boardNum');
            gn = getappdata(figHandle,'gain');
            cbAIn(bn, ch1, gn);
            cbAIn(bn, ch2, gn);
            setStatus(sprintf('MCC détectée | paire AI%d-%d',ch1,ch2), 'green');
        catch ME
            setStatus('Erreur MCC (test lecture). Activez 🧪 Test si besoin.', 'red');
            disp(getReport(ME,'extended'));
        end
    end

    function toggleTestMode(src)
        figHandle = f;
        if getappdata(figHandle,'isRecording')
            btnStart = getappdata(figHandle,'btnStart');
            if ~isempty(btnStart) && isvalid(btnStart)
                btnStart.Value = 0;
                startStopDAQ(btnStart);
            end
        end

        if src.Value==1
            setappdata(figHandle,'test_mode',true);
            sim = buildSimData(getappdata(figHandle,'Fs'));
            setappdata(figHandle,'sim_data',sim);
            setappdata(figHandle,'sim_idx_record',1);
            setappdata(figHandle,'sim_idx_mvc',1);
            setStatus('Mode TEST activé (données simulées).',[0.2 0.2 0.2]);
        else
            setappdata(figHandle,'test_mode',false);
            setappdata(figHandle,'sim_data',[]);
            setappdata(figHandle,'sim_idx_record',1);
            setappdata(figHandle,'sim_idx_mvc',1);
            setStatus('Mode TEST désactivé.',[0.2 0.2 0.2]);
        end
        connectDAQ();
    end

    function [ch1, ch2] = getSelectedPair()
        popupPair = getappdata(f,'popupPair');
        pairIdx = get(popupPair,'Value'); % 1..7 => AI0-1..AI6-7
        ch1 = pairIdx - 1;
        ch2 = ch1 + 1;
    end

    % ============================
    % RECORDING (START/STOP)
    % ============================
    function startStopDAQ(src)
        figHandle = f;

        test_mode = getappdata(figHandle,'test_mode');

        if src.Value
            % START
            setappdata(figHandle,'rawBuf',[]);
            setappdata(figHandle,'sampleIdx',0);
            setappdata(figHandle,'isRecording',true);

            if test_mode
                setappdata(figHandle,'sim_idx_record',1); % record index reset
            end

            resetAllAxes('recording');
            setUIState('recording');

            try
                streamRecording();
            catch ME
                setappdata(figHandle,'isRecording',false);
                setUIState('idle');
                setStatus('Erreur pendant acquisition. Voir console.', 'red');
                disp(getReport(ME,'extended'));
            end

            if ~getappdata(figHandle,'isRecording')
                btnStart = getappdata(figHandle,'btnStart');
                if ~isempty(btnStart) && isvalid(btnStart) && btnStart.Value==1
                    btnStart.Value = 0;
                    startStopDAQ(btnStart);
                end
            end

        else
            % STOP
            setappdata(figHandle,'isRecording',false);
            setUIState('idle');

            rawBuf = getappdata(figHandle,'rawBuf');
            if isempty(rawBuf)
                return
            end

            plotFinalAndStore(rawBuf);
        end
    end

    function streamRecording()
        figHandle = f;

        Fs = getappdata(figHandle,'Fs');
        windowPts = Fs*5;
        chunkPts = 200;
        chunkSec = chunkPts / Fs;

        while getappdata(figHandle,'isRecording') && ishandle(figHandle)
            loopTic = tic;

            rawBuf    = getappdata(figHandle,'rawBuf');
            sampleIdx = getappdata(figHandle,'sampleIdx');

            block = acquireBlockUnified('record', chunkPts); % Nx2
            rawBuf = [rawBuf; block]; %#ok<AGROW>
            setappdata(figHandle,'rawBuf',rawBuf);

            N = size(block,1);
            sampleIdx = sampleIdx + N;
            setappdata(figHandle,'sampleIdx',sampleIdx);

            totalPts = sampleIdx;
            if totalPts <= windowPts
                idx = 1:totalPts;
            else
                idx = (totalPts-windowPts+1):totalPts;
            end

            tsec = (idx-idx(1))/Fs;
            ch1win = rawBuf(idx,1);
            ch2win = rawBuf(idx,2);

            updateLiveRawPlots(tsec, ch1win, ch2win);
            blinkREC();

            drawnow limitrate;

            if getappdata(figHandle,'test_mode')
                elapsed = toc(loopTic);
                pause(max(0, chunkSec - elapsed));
            end
        end
    end

    function updateLiveRawPlots(tsec, y1, y2)
        figHandle = f;
        h1 = getappdata(figHandle,'hLine_raw1');
        h2 = getappdata(figHandle,'hLine_raw2');
        if isempty(h1) || ~isvalid(h1) || isempty(h2) || ~isvalid(h2), return, end
        set(h1,'XData',tsec,'YData',y1,'Color',color_emg1);
        set(h2,'XData',tsec,'YData',y2,'Color',color_emg2);
    end

    function blinkREC()
        figHandle = f;
        recTxt = getappdata(figHandle,'recTxt');
        if isempty(recTxt) || ~isvalid(recTxt), return, end
        blink = getappdata(figHandle,'recBlinkOn');
        if blink
            set(recTxt,'String','');
        else
            set(recTxt,'String','REC ●');
        end
        setappdata(figHandle,'recBlinkOn',~blink);
    end

    function plotFinalAndStore(rawBuf)
        figHandle = f;

        Fs = getappdata(figHandle,'Fs');
        mvc = getappdata(figHandle,'mvc_values');

        emg1_raw = rawBuf(:,1);
        emg2_raw = rawBuf(:,2);

        filt1 = filterEMG(emg1_raw, Fs);
        filt2 = filterEMG(emg2_raw, Fs);

        if ~isempty(mvc)
            if numel(mvc)>=1 && mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
            if numel(mvc)>=2 && mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end
        end

        tsec_raw  = (0:numel(emg1_raw)-1)/Fs;
        tsec_filt = (0:numel(filt1)-1)/Fs;

        ax_raw1  = getappdata(figHandle,'ax_raw1');
        ax_raw2  = getappdata(figHandle,'ax_raw2');
        ax_filt1 = getappdata(figHandle,'ax_filt1');
        ax_filt2 = getappdata(figHandle,'ax_filt2');

        cla(ax_raw1); hold(ax_raw1,'on');
        plotWithOverlay(ax_raw1, tsec_raw, emg1_raw, emg2_raw, color_emg1, color_emg2, ...
            'EMG1 brut', 'Activité (V)');
        set(ax_raw1,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_raw2); hold(ax_raw2,'on');
        plotWithOverlay(ax_raw2, tsec_raw, emg2_raw, emg1_raw, color_emg2, color_emg1, ...
            'EMG2 brut', 'Activité (V)');
        set(ax_raw2,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_filt1); hold(ax_filt1,'on');
        plotWithOverlay(ax_filt1, tsec_filt, filt1, filt2, color_emg1, color_emg2, ...
            'EMG1 filtré (normalisé)', '(%MVC)');
        set(ax_filt1,'XLim',[tsec_filt(1) tsec_filt(end)]);

        cla(ax_filt2); hold(ax_filt2,'on');
        plotWithOverlay(ax_filt2, tsec_filt, filt2, filt1, color_emg2, color_emg1, ...
            'EMG2 filtré (normalisé)', '(%MVC)');
        set(ax_filt2,'XLim',[tsec_filt(1) tsec_filt(end)]);

        rec_count = getappdata(figHandle,'rec_count') + 1;
        setappdata(figHandle,'rec_count',rec_count);

        recs = getappdata(figHandle,'recordings_raw');
        recs{rec_count} = rawBuf; %#ok<AGROW>
        setappdata(figHandle,'recordings_raw',recs);

        assignin('base',sprintf('EMG_recording_raw_%02d',rec_count),rawBuf);
        assignin('base',sprintf('EMG1_filtered_%02d',rec_count),filt1);
        assignin('base',sprintf('EMG2_filtered_%02d',rec_count),filt2);

        assignin('base','EMG_data_raw',rawBuf);
        assignin('base','EMG1_filtered',filt1);
        assignin('base','EMG2_filtered',filt2);

        setStatus(sprintf('Enregistrement #%02d sauvegardé.', rec_count), [0.2 0.2 0.2]);
    end

    function plotWithOverlay(ax, t, yMain, yOther, colMain, colOther, titleStr, yLabelStr)
        plot(ax, t, yMain, '-', 'Color', colMain);
        h = plot(ax, t, yOther, '-', 'Color', colOther);
        setLineAlphaOrLighten(h, colOther, alpha_overlay);
        applyAxisStyle(ax, titleStr, colMain, yLabelStr);
    end

    % ============================
    % MVC
    % ============================
    function measureMVC(whichMVC)
        % Robust figure retrieval (in case callback context changes)
        figHandle = gcbf;
        if isempty(figHandle) || ~ishandle(figHandle)
            figHandle = f;
        end
        if isempty(figHandle) || ~ishandle(figHandle)
            return
        end

        % Ensure sim MVC index resets for each MVC in test mode
        if getappdata(figHandle,'test_mode')
            setappdata(figHandle,'sim_idx_mvc',1);
        end

        setUIState('mvc');
        setStatus(sprintf('Mesure MVC%d en cours (5 s)...', whichMVC), [0.2 0.2 0.2]);

        % Only reset axes for visual clarity (not mandatory)
        resetAllAxes('mvc');

        Fs = getappdata(figHandle,'Fs');
        durSec = 5;
        nPts = durSec*Fs;

        chunkPts = 200;
        chunkSec = chunkPts / Fs;

        % MVC1 uses EMG1 (col 1), MVC2 uses EMG2 (col 2)
        targetCol = whichMVC;

        if whichMVC==1
            targetRaw  = getappdata(figHandle,'ax_raw1');
            targetFilt = getappdata(figHandle,'ax_filt1');
            col = color_emg1;
        else
            targetRaw  = getappdata(figHandle,'ax_raw2');
            targetFilt = getappdata(figHandle,'ax_filt2');
            col = color_emg2;
        end

        cla(targetRaw);  hold(targetRaw,'on');
        cla(targetFilt); hold(targetFilt,'on');

        hRaw  = plot(targetRaw,nan,nan,'-','Color',col);
        hFilt = plot(targetFilt,nan,nan,'-','Color',col);

        applyAxisStyle(targetRaw,  sprintf('EMG%d MVC (%ds)',whichMVC,durSec), col, 'Activité (V)');
        applyAxisStyle(targetFilt, sprintf('EMG%d enveloppe MVC',whichMVC),      col, '(%MVC)');
        set(targetRaw,'XLim',[0 durSec]);
        set(targetFilt,'XLim',[0 durSec]);

        buf = [];
        idx = 1;

        try
            while idx <= nPts && ishandle(figHandle)
                loopTic = tic;

                idxEnd = min(idx + chunkPts - 1, nPts);
                nThis = idxEnd - idx + 1;

                block = acquireBlockUnified('mvc', nThis); % Nx2
                newy = block(:, targetCol);

                buf = [buf; newy]; %#ok<AGROW>

                tsec = (0:numel(buf)-1)/Fs;
                set(hRaw,'XData',tsec,'YData',buf);

                env = sqrt(movmean((buf-mean(buf)).^2,100));
                set(hFilt,'XData',tsec,'YData',env);

                drawnow limitrate;

                if getappdata(figHandle,'test_mode')
                    elapsed = toc(loopTic);
                    pause(max(0, chunkSec - elapsed));
                end

                idx = idxEnd + 1;
            end
        catch ME
            setUIState('idle');
            setStatus('Erreur pendant MVC. Voir console.', 'red');
            disp(getReport(ME,'extended'));
            return
        end

        if isempty(buf) || all(~isfinite(buf))
            setUIState('idle');
            setStatus(sprintf('MVC%d non mesuré (pas de signal).',whichMVC), 'red');
            return
        end

        nTake = min(2000,numel(buf));
        topVals = maxk(abs(buf),nTake);
        mvcVal = median(topVals);

        mvc = getappdata(figHandle,'mvc_values');
        if isempty(mvc), mvc=[0 0]; end
        mvc(whichMVC) = mvcVal;
        setappdata(figHandle,'mvc_values',mvc);

        mvcTxt = getappdata(figHandle,'mvcTxt');
        if ~isempty(mvcTxt) && isvalid(mvcTxt)
            set(mvcTxt,'String',sprintf('MVC1 = %.2f | MVC2 = %.2f',mvc(1),mvc(2)));
        end

        setUIState('idle');
        setStatus(sprintf('MVC%d mesuré.', whichMVC), [0.2 0.2 0.2]);
    end

    % ============================
    % ACQUISITION UNIFIED (TEST/HW)
    % ============================
    function block = acquireBlockUnified(kind, nPts)
        % kind: 'record' or 'mvc'
        % Returns nPts x 2 [EMG1 EMG2]
        figHandle = f;
        Fs = getappdata(figHandle,'Fs');
        test_mode = getappdata(figHandle,'test_mode');

        if test_mode
            sim = getappdata(figHandle,'sim_data');
            if isempty(sim)
                sim = buildSimData(Fs);
                setappdata(figHandle,'sim_data',sim);
                setappdata(figHandle,'sim_idx_record',1);
                setappdata(figHandle,'sim_idx_mvc',1);
            end

            switch kind
                case 'record'
                    idx0 = getappdata(figHandle,'sim_idx_record');
                case 'mvc'
                    idx0 = getappdata(figHandle,'sim_idx_mvc');
                otherwise
                    error('Unknown acquisition kind: %s', kind);
            end

            idx1 = idx0 + nPts - 1;

            switch kind
                case 'record'
                    sig1 = sim.rec1; sig2 = sim.rec2;
                case 'mvc'
                    sig1 = sim.mvc1; sig2 = sim.mvc2;
            end

            if idx1 > numel(sig1)
                block = zeros(nPts,2);
                return
            end

            block = [sig1(idx0:idx1), sig2(idx0:idx1)];

            switch kind
                case 'record'
                    setappdata(figHandle,'sim_idx_record',idx1+1);
                case 'mvc'
                    setappdata(figHandle,'sim_idx_mvc',idx1+1);
            end

        else
            bn = getappdata(figHandle,'boardNum');
            gn = getappdata(figHandle,'gain');
            ch1 = getappdata(figHandle,'chanNum1');
            ch2 = getappdata(figHandle,'chanNum2');

            if ~(exist('cbAInScan','file')==2 || exist('cbAInScan','file')==3)
                error('cbAInScan introuvable. Installez MCC UL ou activez TEST.');
            end

            v1 = acquireOneChannel(bn, ch1, gn, Fs, nPts);
            v2 = acquireOneChannel(bn, ch2, gn, Fs, nPts);
            block = [v1(:), v2(:)];
        end
    end

    % ============================
    % CLOSE HANDLER
    % ============================
    function onClose(~,~)
        setappdata(f,'isRecording',false);
        try setUIState('idle'); catch, end
        delete(f);
    end
end

% =========================================================================
% HARDWARE ACQUISITION (MCC UL)
% =========================================================================
function v = acquireOneChannel(boardNum, physCh, gain, Fs, nPts)
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
            v = (rawCounts - 2048) / 2048 * 10;
        end
    catch ME
        try cbWinBufFree(memHandle); catch, end
        rethrow(ME);
    end
end

function gain = getDefaultGain()
    gain = 1;
    try
        if exist('BIP10VOLTS','var') %#ok<EXIST>
            gain = BIP10VOLTS;
        end
    catch
    end
end

% =========================================================================
% EMG FILTERING
% =========================================================================
function filtered = filterEMG(raw, Fs)
    raw = raw - mean(raw);

    f0 = 60;
    Q  = 2;
    wo = f0/(Fs/2);
    bw = wo/Q;

    if exist('iirnotch','file')==2
        [b,a] = iirnotch(wo,bw);
        emg_notch = filtfilt(b,a,raw);
    else
        d = designfilt('bandstopiir', ...
            'FilterOrder',2, ...
            'HalfPowerFrequency1',f0-1.5, ...
            'HalfPowerFrequency2',f0+1.5, ...
            'SampleRate',Fs);
        emg_notch = filtfilt(d,raw);
    end

    [b,a] = butter(4,[20 400]/(Fs/2),'bandpass');
    emg = filtfilt(b,a,emg_notch);

    filtered = sqrt(movmean(emg.^2,100));
end

% =========================================================================
% EXPORTS
% =========================================================================
function exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2)
    fig = figure('Visible','off','Position',[100,100,1200,800]);
    subplot(2,2,1); copyobj(allchild(ax_raw1), gca);
    title('EMG1 brut'); xlabel('Temps (s)'); ylabel('Activité (V)');
    subplot(2,2,2); copyobj(allchild(ax_raw2), gca);
    title('EMG2 brut'); xlabel('Temps (s)'); ylabel('Activité (V)');
    subplot(2,2,3); copyobj(allchild(ax_filt1), gca);
    title('EMG1 filtré (normalisé)'); xlabel('Temps (s)'); ylabel('(%MVC)');
    subplot(2,2,4); copyobj(allchild(ax_filt2), gca);
    title('EMG2 filtré (normalisé)'); xlabel('Temps (s)'); ylabel('(%MVC)');

    [file,path] = uiputfile('*.png','Exporter les graphiques sous...');
    if ~isequal(file,0)
        saveas(fig, fullfile(path,file));
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
    rawBuf = recs{end};
    emg1_raw = rawBuf(:,1);
    emg2_raw = rawBuf(:,2);

    filt1 = filterEMG(emg1_raw, Fs);
    filt2 = filterEMG(emg2_raw, Fs);

    mvc = getappdata(figHandle,'mvc_values');
    if ~isempty(mvc)
        if numel(mvc)>=1 && mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
        if numel(mvc)>=2 && mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end
    end

    t = (0:size(rawBuf,1)-1)'/Fs;
    T = table(t, emg1_raw, emg2_raw, filt1, filt2, ...
        'VariableNames', {'time_s','emg1_raw_V','emg2_raw_V','emg1_filt_pctMVC','emg2_filt_pctMVC'});

    [file,path] = uiputfile('*.csv','Exporter CSV sous...');
    if isequal(file,0), return, end
    writetable(T, fullfile(path,file));
end

% =========================================================================
% PLOTTING HELPER (SIMULATED "ALPHA" VIA LIGHTENING)
% =========================================================================
function setLineAlphaOrLighten(h, rgb, alpha)
    rgb2 = rgb + (1-rgb)*(1-alpha);
    set(h,'Color',rgb2);
end

% =========================================================================
% SIMULATION GENERATOR
% =========================================================================
function sim = buildSimData(Fs)
    rng(1);

    noiseStd = 0.2;
    f_line   = 60;
    lineAmp  = 0.3;

    % MVC 5s: ramp 1s, hold 3s, rest 1s (amplitude changes; mean ~ 0)
    durMVC = 5; Nmvc = durMVC*Fs; tMVC = (0:Nmvc-1)'/Fs;
    env = zeros(Nmvc,1);
    env(1:Fs) = linspace(0,1,Fs)';                  % ramp
    env(Fs+1:Fs+3*Fs) = 1;                           % hold
    env(Fs+3*Fs+1:Fs+4*Fs) = 0;                      % rest

    A1 = 2.0; A2 = 3.0;
    mvc1 = (A1*env).*randn(Nmvc,1) + noiseStd*randn(Nmvc,1);
    mvc2 = (A2*env).*randn(Nmvc,1) + noiseStd*randn(Nmvc,1) + lineAmp*sin(2*pi*f_line*tMVC);

    mvc1 = mvc1 - mean(mvc1);
    mvc2 = mvc2 - mean(mvc2);

    % Recording 5s
    durRec = 5; Nrec = durRec*Fs; tRec = (0:Nrec-1)'/Fs;
    rec1 = noiseStd*randn(Nrec,1);
    rec2 = noiseStd*randn(Nrec,1) + lineAmp*sin(2*pi*f_line*tRec);

    % Muscle1 bursts: 2 bursts of 1.5V, 1s each
    burstA1 = 1.5; nb1 = round(1.0*Fs);
    starts1 = round([1.0 3.0]*Fs);
    car1 = randn(Nrec,1);
    for s = starts1
        idx = s + (1:nb1);
        idx(idx>Nrec) = [];
        rec1(idx) = rec1(idx) + burstA1*car1(idx);
    end

    % Muscle2 bursts: 4 bursts of 0.5V, 0.7s each
    burstA2 = 0.5; nb2 = round(0.7*Fs);
    starts2 = round([0.6 1.7 2.8 3.9]*Fs);
    car2 = randn(Nrec,1);
    for s = starts2
        idx = s + (1:nb2);
        idx(idx>Nrec) = [];
        rec2(idx) = rec2(idx) + burstA2*car2(idx);
    end

    rec1 = rec1 - mean(rec1);
    rec2 = rec2 - mean(rec2);

    sim = struct('Fs',Fs,'tMVC',tMVC,'mvc1',mvc1,'mvc2',mvc2,'tRec',tRec,'rec1',rec1,'rec2',rec2);
end
