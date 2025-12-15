function EMG_GUI_digilent()
% EMG GUI — Digilent/MCC (USB-1208FS-PLUS) OR TEST MODE (no hardware)
%
% This version:
% - TEST mode streams at REAL TIME speed using pause() pacing
% - Recording shows RAW (top) + FILTERED+NORMALISED (bottom) LIVE, like MVC
% - MVC streaming uses separate sim index (sim_idx_mvc) from recording (sim_idx_record)

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
    setappdata(f,'sim_idx_record',1);  % record index
    setappdata(f,'sim_idx_mvc',1);     % MVC index (separate!)
    setappdata(f,'recBlinkOn',false);

    %% Build UI & connect
    buildUI();
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

        % Initial axes labels/titles + create live lines
        resetAllAxes('idle');
    end

    % ============================
    % UI STATE HELPERS
    % ============================
    function setStatus(msg, colorNameOrRGB)
        statusTxt = getappdata(f,'statusTxt');
        if isempty(statusTxt) || ~isvalid(statusTxt), return, end
        set(statusTxt,'String',msg);
        if nargin>=2
            set(statusTxt,'ForegroundColor',colorNameOrRGB);
        end
    end

    function setUIState(state)
        popupPair = getappdata(f,'popupPair');
        btnStart  = getappdata(f,'btnStart');
        recTxt    = getappdata(f,'recTxt');

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
                setappdata(f,'recBlinkOn',false);

            case 'recording'
                set(popupPair,'Enable','off');
                if ~isempty(btnStart) && isvalid(btnStart)
                    btnStart.String = '⏹ Stop';
                end
                if ~isempty(recTxt) && isvalid(recTxt)
                    set(recTxt,'String','REC ●');
                end
                setappdata(f,'recBlinkOn',true);

            case 'mvc'
                set(popupPair,'Enable','off');
        end
    end

    function resetAllAxes(context)
        ax_raw1  = getappdata(f,'ax_raw1');
        ax_raw2  = getappdata(f,'ax_raw2');
        ax_filt1 = getappdata(f,'ax_filt1');
        ax_filt2 = getappdata(f,'ax_filt2');

        cla(ax_raw1);  hold(ax_raw1,'on');
        cla(ax_raw2);  hold(ax_raw2,'on');
        cla(ax_filt1); hold(ax_filt1,'on');
        cla(ax_filt2); hold(ax_filt2,'on');

        applyAxisStyle(ax_raw1,  'EMG1 brut', color_emg1, 'Activité (V)');
        applyAxisStyle(ax_raw2,  'EMG2 brut', color_emg2, 'Activité (V)');
        applyAxisStyle(ax_filt1, 'EMG1 filtré (normalisé)', color_emg1, '(%MVC)');
        applyAxisStyle(ax_filt2, 'EMG2 filtré (normalisé)', color_emg2, '(%MVC)');

        % Live lines (raw + filt)
        hLine_raw1  = plot(ax_raw1, nan, nan, '-', 'Color', color_emg1);
        hLine_raw2  = plot(ax_raw2, nan, nan, '-', 'Color', color_emg2);
        hLine_filt1 = plot(ax_filt1,nan, nan, '-', 'Color', color_emg1);
        hLine_filt2 = plot(ax_filt2,nan, nan, '-', 'Color', color_emg2);

        setappdata(f,'hLine_raw1',hLine_raw1);
        setappdata(f,'hLine_raw2',hLine_raw2);
        setappdata(f,'hLine_filt1',hLine_filt1);
        setappdata(f,'hLine_filt2',hLine_filt2);

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

    function blinkREC()
        recTxt = getappdata(f,'recTxt');
        if isempty(recTxt) || ~isvalid(recTxt), return, end
        blink = getappdata(f,'recBlinkOn');
        if blink
            set(recTxt,'String','');
        else
            set(recTxt,'String','REC ●');
        end
        setappdata(f,'recBlinkOn',~blink);
    end

    % ============================
    % CONNECT / TEST MODE
    % ============================
    function connectDAQ()
        [ch1, ch2] = getSelectedPair();
        setappdata(f,'chanNum1',ch1);
        setappdata(f,'chanNum2',ch2);

        if getappdata(f,'test_mode')
            setStatus(sprintf('Mode TEST (simulé) | paire AI%d-%d',ch1,ch2), [0.2 0.2 0.2]);
            return
        end

        if ~(exist('cbAIn','file')==2 || exist('cbAIn','file')==3)
            setStatus('MCC UL introuvable (cbAIn). Activez 🧪 Test ou installez MCC UL.', 'red');
            return
        end

        try
            try cbErrHandling(0,0); catch, end
            bn = getappdata(f,'boardNum');
            gn = getappdata(f,'gain');
            cbAIn(bn, ch1, gn);
            cbAIn(bn, ch2, gn);
            setStatus(sprintf('MCC détectée | paire AI%d-%d',ch1,ch2), 'green');
        catch ME
            setStatus('Erreur MCC (test lecture). Activez 🧪 Test si besoin.', 'red');
            disp(getReport(ME,'extended'));
        end
    end

    function toggleTestMode(src)
        if getappdata(f,'isRecording')
            btnStart = getappdata(f,'btnStart');
            if ~isempty(btnStart) && isvalid(btnStart)
                btnStart.Value = 0;
                startStopDAQ(btnStart);
            end
        end

        if src.Value==1
            setappdata(f,'test_mode',true);
            sim = buildSimData(getappdata(f,'Fs'));
            setappdata(f,'sim_data',sim);
            setappdata(f,'sim_idx_record',1);
            setappdata(f,'sim_idx_mvc',1);
            setStatus('Mode TEST activé (données simulées).',[0.2 0.2 0.2]);
        else
            setappdata(f,'test_mode',false);
            setappdata(f,'sim_data',[]);
            setappdata(f,'sim_idx_record',1);
            setappdata(f,'sim_idx_mvc',1);
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
        test_mode = getappdata(f,'test_mode');

        if src.Value
            % START
            setappdata(f,'rawBuf',[]);
            setappdata(f,'sampleIdx',0);
            setappdata(f,'isRecording',true);

            if test_mode
                setappdata(f,'sim_idx_record',1);
            end

            resetAllAxes('recording');
            setUIState('recording');

            try
                streamRecording();
            catch ME
                setappdata(f,'isRecording',false);
                setUIState('idle');
                setStatus('Erreur pendant acquisition. Voir console.', 'red');
                disp(getReport(ME,'extended'));
            end

            if ~getappdata(f,'isRecording')
                btnStart = getappdata(f,'btnStart');
                if ~isempty(btnStart) && isvalid(btnStart) && btnStart.Value==1
                    btnStart.Value = 0;
                    startStopDAQ(btnStart);
                end
            end

        else
            % STOP
            setappdata(f,'isRecording',false);
            setUIState('idle');

            rawBuf = getappdata(f,'rawBuf');
            if isempty(rawBuf)
                return
            end

            plotFinalAndStore(rawBuf);
        end
    end

    function streamRecording()
        Fs = getappdata(f,'Fs');
        windowPts = Fs*5;
        chunkPts = 200;
        chunkSec = chunkPts / Fs;

        while getappdata(f,'isRecording') && ishandle(f)
            loopTic = tic;

            rawBuf    = getappdata(f,'rawBuf');
            sampleIdx = getappdata(f,'sampleIdx');

            block = acquireBlockUnified('record', chunkPts); % Nx2
            rawBuf = [rawBuf; block]; %#ok<AGROW>
            setappdata(f,'rawBuf',rawBuf);

            N = size(block,1);
            sampleIdx = sampleIdx + N;
            setappdata(f,'sampleIdx',sampleIdx);

            totalPts = sampleIdx;
            if totalPts <= windowPts
                idx = 1:totalPts;
            else
                idx = (totalPts-windowPts+1):totalPts;
            end

            tsec = (idx-idx(1))/Fs;

            ch1win = rawBuf(idx,1);
            ch2win = rawBuf(idx,2);

            % --- RAW LIVE ---
            h1 = getappdata(f,'hLine_raw1');
            h2 = getappdata(f,'hLine_raw2');
            if ~isempty(h1) && isvalid(h1), set(h1,'XData',tsec,'YData',ch1win,'Color',color_emg1); end
            if ~isempty(h2) && isvalid(h2), set(h2,'XData',tsec,'YData',ch2win,'Color',color_emg2); end

            % --- FILTERED + NORMALISED LIVE (like MVC) ---
            mvc = getappdata(f,'mvc_values');
            if isempty(mvc), mvc = [0 0]; end

            filt1 = filterEMG(ch1win, Fs);
            filt2 = filterEMG(ch2win, Fs);

            if mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
            if mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end

            hf1 = getappdata(f,'hLine_filt1');
            hf2 = getappdata(f,'hLine_filt2');
            if ~isempty(hf1) && isvalid(hf1), set(hf1,'XData',tsec,'YData',filt1,'Color',color_emg1); end
            if ~isempty(hf2) && isvalid(hf2), set(hf2,'XData',tsec,'YData',filt2,'Color',color_emg2); end

            blinkREC();
            drawnow limitrate;

            if getappdata(f,'test_mode')
                elapsed = toc(loopTic);
                pause(max(0, chunkSec - elapsed));
            end
        end
    end

    function plotFinalAndStore(rawBuf)
        Fs = getappdata(f,'Fs');
        mvc = getappdata(f,'mvc_values');

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

        ax_raw1  = getappdata(f,'ax_raw1');
        ax_raw2  = getappdata(f,'ax_raw2');
        ax_filt1 = getappdata(f,'ax_filt1');
        ax_filt2 = getappdata(f,'ax_filt2');

        cla(ax_raw1); hold(ax_raw1,'on');
        plot(ax_raw1, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
        h = plot(ax_raw1, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
        setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
        applyAxisStyle(ax_raw1,'EMG1 brut', color_emg1, 'Activité (V)');
        set(ax_raw1,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_raw2); hold(ax_raw2,'on');
        plot(ax_raw2, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
        h = plot(ax_raw2, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
        setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
        applyAxisStyle(ax_raw2,'EMG2 brut', color_emg2, 'Activité (V)');
        set(ax_raw2,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_filt1); hold(ax_filt1,'on');
        plot(ax_filt1, tsec_filt, filt1, '-', 'Color', color_emg1);
        h = plot(ax_filt1, tsec_filt, filt2, '-', 'Color', color_emg2);
        setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
        applyAxisStyle(ax_filt1,'EMG1 filtré (normalisé)', color_emg1, '(%MVC)');
        set(ax_filt1,'XLim',[tsec_filt(1) tsec_filt(end)]);

        cla(ax_filt2); hold(ax_filt2,'on');
        plot(ax_filt2, tsec_filt, filt2, '-', 'Color', color_emg2);
        h = plot(ax_filt2, tsec_filt, filt1, '-', 'Color', color_emg1);
        setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
        applyAxisStyle(ax_filt2,'EMG2 filtré (normalisé)', color_emg2, '(%MVC)');
        set(ax_filt2,'XLim',[tsec_filt(1) tsec_filt(end)]);

        rec_count = getappdata(f,'rec_count') + 1;
        setappdata(f,'rec_count',rec_count);

        recs = getappdata(f,'recordings_raw');
        recs{rec_count} = rawBuf; %#ok<AGROW>
        setappdata(f,'recordings_raw',recs);

        assignin('base',sprintf('EMG_recording_raw_%02d',rec_count),rawBuf);
        assignin('base',sprintf('EMG1_filtered_%02d',rec_count),filt1);
        assignin('base',sprintf('EMG2_filtered_%02d',rec_count),filt2);

        assignin('base','EMG_data_raw',rawBuf);
        assignin('base','EMG1_filtered',filt1);
        assignin('base','EMG2_filtered',filt2);

        setStatus(sprintf('Enregistrement #%02d sauvegardé.', rec_count), [0.2 0.2 0.2]);
    end

    % ============================
    % MVC
    % ============================
    function measureMVC(whichMVC)
        figHandle = gcbf;
        if isempty(figHandle) || ~ishandle(figHandle)
            figHandle = f;
        end
        if isempty(figHandle) || ~ishandle(figHandle)
            return
        end

        if getappdata(figHandle,'test_mode')
            setappdata(figHandle,'sim_idx_mvc',1); % reset MVC stream index
        end

        setUIState('mvc');
        setStatus(sprintf('Mesure MVC%d en cours (5 s)...', whichMVC), [0.2 0.2 0.2]);

        resetAllAxes('mvc');

        Fs = getappdata(figHandle,'Fs');
        durSec = 5;
        nPts = durSec*Fs;

        chunkPts = 200;
        chunkSec = chunkPts / Fs;

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
    % ACQUISITION UNIFIED
    % ============================
    function block = acquireBlockUnified(kind, nPts)
        Fs = getappdata(f,'Fs');
        test_mode = getappdata(f,'test_mode');

        if test_mode
            sim = getappdata(f,'sim_data');
            if isempty(sim)
                sim = buildSimData(Fs);
                setappdata(f,'sim_data',sim);
                setappdata(f,'sim_idx_record',1);
                setappdata(f,'sim_idx_mvc',1);
            end

            switch kind
                case 'record'
                    idx0 = getappdata(f,'sim_idx_record');
                    sig1 = sim.rec1; sig2 = sim.rec2;
                case 'mvc'
                    idx0 = getappdata(f,'sim_idx_mvc');
                    sig1 = sim.mvc1; sig2 = sim.mvc2;
                otherwise
                    error('Unknown acquisition kind: %s', kind);
            end

            idx1 = idx0 + nPts - 1;
            if idx1 > numel(sig1)
                block = zeros(nPts,2);
                return
            end

            block = [sig1(idx0:idx1), sig2(idx0:idx1)];

            if strcmp(kind,'record')
                setappdata(f,'sim_idx_record',idx1+1);
            else
                setappdata(f,'sim_idx_mvc',idx1+1);
            end

        else
            bn = getappdata(f,'boardNum');
            gn = getappdata(f,'gain');
            ch1 = getappdata(f,'chanNum1');
            ch2 = getappdata(f,'chanNum2');

            if ~(exist('cbAInScan','file')==2 || exist('cbAInScan','file')==3)
                error('cbAInScan introuvable. Installez MCC UL ou activez TEST.');
            end

            v1 = acquireOneChannel(bn, ch1, gn, Fs, nPts);
            v2 = acquireOneChannel(bn, ch2, gn, Fs, nPts);
            block = [v1(:), v2(:)];
        end
    end

    % ============================
    % CLOSE
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

function setLineAlphaOrLighten(h, rgb, alpha)
    try
        set(h,'Color',[rgb alpha]);
    catch
        rgb2 = rgb + (1-rgb)*(1-alpha);
        set(h,'Color',rgb2);
    end
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

    % Muscle1 bursts
    burstA1 = 1.5; nb1 = round(1.0*Fs);
    starts1 = round([1.0 3.0]*Fs);
    car1 = randn(Nrec,1);
    for s = starts1
        idx = s + (1:nb1);
        idx(idx>Nrec) = [];
        rec1(idx) = rec1(idx) + burstA1*car1(idx);
    end

    % Muscle2 bursts
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
