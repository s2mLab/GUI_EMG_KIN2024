function EMG_GUI_digilent()
% EMG GUI — Digilent/MCC (USB-1208FS-PLUS) OR TEST MODE (no hardware)
% FIXES in this version:
% - Adds the missing measureMVC() function (was referenced but not defined)
% - Moves top-row controls from y=0.90 to y=0.95 (popup + buttons + labels)

    f = figure('Name','EMG Acquisition','NumberTitle','off', ...
        'Position',[100,100,900,700],'Units','normalized');

    %% Colours
    color_emg1 = [0 0.4470 0.7410];
    color_emg2 = [0.8500 0.3250 0.0980];
    alpha_overlay = 0.10;
    setappdata(f,'color_emg1',color_emg1);
    setappdata(f,'color_emg2',color_emg2);
    setappdata(f,'alpha_overlay',alpha_overlay);

    %% Status + MVC + REC
    statusTxt = uicontrol(f,'Style','text','String','Prêt. Activez 🧪 Test si pas de carte.', ...
        'Units','normalized','Position',[0.05,0.94,0.35,0.04], ...
        'FontSize',12,'HorizontalAlignment','left');

    recTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.40,0.94,0.15,0.04], ...
        'FontSize',12,'FontWeight','bold','HorizontalAlignment','left', ...
        'ForegroundColor',[1 0 0]);
    setappdata(f,'recTxt',recTxt);
    setappdata(f,'recBlinkOn',false);

    mvcTxt = uicontrol(f,'Style','text','String','', ...
        'Units','normalized','Position',[0.58,0.94,0.4,0.04], ...
        'FontSize',12,'HorizontalAlignment','left');

    %% Popup pair (moved to y=0.95)
    pairList = arrayfun(@(k) sprintf('AI%d-%d',k,k+1), 0:6, 'UniformOutput', false);
    uicontrol(f,'Style','text','String','Paire EMG:', ...
        'Units','normalized','Position',[0.05,0.905,0.08,0.035],'HorizontalAlignment','left');

    popupPair = uicontrol(f,'Style','popupmenu','String',pairList, ...
        'Units','normalized','Position',[0.13,0.9,0.10,0.045], ...
        'FontSize',11,'Value',1, ...
        'Callback',@(~,~) connectDAQ());
    setappdata(f,'popupPair',popupPair);

    %% Axes
    ax_raw1 = axes(f,'Units','normalized','Position',[0.07,0.58,0.40,0.30]); hold(ax_raw1,'on');
    t = title(ax_raw1,'EMG1 brut'); set(t,'Color',color_emg1);
    xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');
    hLine_raw1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1);

    ax_raw2 = axes(f,'Units','normalized','Position',[0.53,0.58,0.40,0.30]); hold(ax_raw2,'on');
    t = title(ax_raw2,'EMG2 brut'); set(t,'Color',color_emg2);
    xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');
    hLine_raw2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2);

    ax_filt1 = axes(f,'Units','normalized','Position',[0.07,0.15,0.40,0.30]); hold(ax_filt1,'on');
    t = title(ax_filt1,'EMG1 filtré (normalisé)'); set(t,'Color',color_emg1);
    xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');

    ax_filt2 = axes(f,'Units','normalized','Position',[0.53,0.15,0.40,0.30]); hold(ax_filt2,'on');
    t = title(ax_filt2,'EMG2 filtré (normalisé)'); set(t,'Color',color_emg2);
    xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

    setappdata(f,'ax_raw1',ax_raw1);
    setappdata(f,'ax_raw2',ax_raw2);
    setappdata(f,'ax_filt1',ax_filt1);
    setappdata(f,'ax_filt2',ax_filt2);
    setappdata(f,'hLine_raw1',hLine_raw1);
    setappdata(f,'hLine_raw2',hLine_raw2);

    %% Sampling / MCC config
    Fs = 2000;
    setappdata(f,'Fs',Fs);

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

    %% State
    setappdata(f,'mvc_values',[0 0]);
    setappdata(f,'rec_count',0);
    setappdata(f,'recordings_raw',{});
    setappdata(f,'rawBuf',[]);
    setappdata(f,'sampleIdx',0);
    setappdata(f,'test_mode',false);
    setappdata(f,'isRecording',false);

    setappdata(f,'sim_data',[]);
    setappdata(f,'sim_idx_record',1);

    %% Buttons (moved to y=0.95; height already reduced)
    btnTest = uicontrol(f,'Style','togglebutton','String','🧪 Test', ...
        'Units','normalized','Position',[0.46,0.95,0.07,0.0355],'FontSize',11, ...
        'Callback',@(src,~) toggleTestMode(src,statusTxt));
    setappdata(f,'btnTest',btnTest);

    btnStart = uicontrol(f,'Style','togglebutton','String','⏺ Enregistrer', ...
        'Units','normalized','Position',[0.54,0.95,0.20,0.035],'FontSize',12, ...
        'Callback',@(src,~) startStopDAQ(src,statusTxt));
    setappdata(f,'btnStart',btnStart);

    uicontrol(f,'Style','pushbutton','String','MVC 1', ...
        'Units','normalized','Position',[0.76,0.95,0.08,0.035],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,1));

    uicontrol(f,'Style','pushbutton','String','MVC 2', ...
        'Units','normalized','Position',[0.85,0.95,0.08,0.035],'FontSize',12, ...
        'Callback',@(~,~) measureMVC(f,mvcTxt,2));

    %% Bottom buttons
    uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
        'Units','normalized','Position',[0.60,0.02,0.18,0.035],'FontSize',12, ...
        'Callback',@(~,~) exportGraphs(ax_raw1,ax_raw2,ax_filt1,ax_filt2));

    uicontrol(f,'Style','pushbutton','String','Exporter CSV', ...
        'Units','normalized','Position',[0.80,0.02,0.18,0.035],'FontSize',12, ...
        'Callback',@(~,~) exportCSV(f));

    %% initial channel selection only
    connectDAQ();
    setappdata(f,'connectFcn', @connectDAQ);

    %% -------- nested: connectDAQ --------
    function connectDAQ()
        pairIdx = get(getappdata(f,'popupPair'),'Value'); % 1..7 => AI0-1..AI6-7
        ch1 = pairIdx - 1;
        ch2 = ch1 + 1;
        setappdata(f,'chanNum1',ch1);
        setappdata(f,'chanNum2',ch2);

        if getappdata(f,'test_mode')
            set(statusTxt,'String',sprintf('Mode TEST (simulé) | paire AI%d-%d',ch1,ch2), ...
                'ForegroundColor',[0.2 0.2 0.2]);
            return
        end

        if ~(exist('cbAIn','file')==2 || exist('cbAIn','file')==3)
            set(statusTxt,'String','MCC Universal Library introuvable (cbAIn). Activez 🧪 Test ou installez MCC UL.', ...
                'ForegroundColor','red');
            return
        end

        try
            try cbErrHandling(0,0); catch, end
            bn = getappdata(f,'boardNum');
            gn = getappdata(f,'gain');
            cbAIn(bn, ch1, gn);
            cbAIn(bn, ch2, gn);
            set(statusTxt,'String',sprintf('MCC détectée | paire AI%d-%d',ch1,ch2), 'ForegroundColor','green');
        catch ME
            set(statusTxt,'String','Erreur MCC (test lecture). Activez 🧪 Test si besoin.', 'ForegroundColor','red');
            disp(getReport(ME,'extended'));
        end
    end

    %% -------- nested: toggle test mode --------
    function toggleTestMode(src, statusTxtLocal)
        btnStartLocal = getappdata(f,'btnStart');
        if ~isempty(btnStartLocal) && isvalid(btnStartLocal) && btnStartLocal.Value==1
            btnStartLocal.Value = 0;
            startStopDAQ(btnStartLocal,statusTxtLocal);
        end

        if src.Value==1
            setappdata(f,'test_mode',true);
            sim = buildSimData(getappdata(f,'Fs'));
            setappdata(f,'sim_data',sim);
            setappdata(f,'sim_idx_record',1);
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

    if ~test_mode && ~(exist('cbAInScan','file')==2 || exist('cbAInScan','file')==3)
        set(statusTxt,'String','cbAInScan introuvable. Installez MCC UL ou activez 🧪 Test.','ForegroundColor','red');
        src.Value = 0;
        src.String = '⏺ Enregistrer';
        return
    end

    windowPts = Fs*5;
    chunkPts  = 200;

    if src.Value
        setappdata(fig,'rawBuf',[]);
        setappdata(fig,'sampleIdx',0);
        setappdata(fig,'isRecording',true);

        src.String = '⏹ Stop';
        set(popupPair,'Enable','off');

        set(recTxt,'String','REC ●');
        setappdata(fig,'recBlinkOn',true);

        cla(ax_raw1); hold(ax_raw1,'on'); title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');
        cla(ax_raw2); hold(ax_raw2,'on'); title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');
        cla(ax_filt1); title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');
        cla(ax_filt2); title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

        hLine1 = plot(ax_raw1,nan,nan,'-','Color',color_emg1); setappdata(fig,'hLine_raw1',hLine1);
        hLine2 = plot(ax_raw2,nan,nan,'-','Color',color_emg2); setappdata(fig,'hLine_raw2',hLine2);

        set(ax_raw1,'XLim',[0 5]);
        set(ax_raw2,'XLim',[0 5]);

        if test_mode
            setappdata(fig,'sim_idx_record',1);
        end

        while getappdata(fig,'isRecording') && ishandle(fig)
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
                    setappdata(fig,'isRecording',false);
                    break
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

            tsec = (idx-idx(1))/Fs;
            ch1win = rawBuf(idx,1);
            ch2win = rawBuf(idx,2);

            if ~isempty(ch1win)
                set(hLine1,'XData',tsec,'YData',ch1win,'Color',color_emg1);
            end
            if ~isempty(ch2win)
                set(hLine2,'XData',tsec,'YData',ch2win,'Color',color_emg2);
            end

            blink = getappdata(fig,'recBlinkOn');
            if blink, set(recTxt,'String',''); else, set(recTxt,'String','REC ●'); end
            setappdata(fig,'recBlinkOn',~blink);

            drawnow limitrate;
        end

        if src.Value==1 && ~getappdata(fig,'isRecording')
            src.Value = 0;
            startStopDAQ(src,statusTxt);
        end

    else
        setappdata(fig,'isRecording',false);

        src.String = '⏺ Enregistrer';
        set(popupPair,'Enable','on');

        set(recTxt,'String','');
        setappdata(fig,'recBlinkOn',false);

        rawBuf = getappdata(fig,'rawBuf');
        if isempty(rawBuf), return, end

        emg1_raw = rawBuf(:,1);
        emg2_raw = rawBuf(:,2);

        filt1 = filterEMG(emg1_raw, Fs);
        filt2 = filterEMG(emg2_raw, Fs);

        mvc = getappdata(fig,'mvc_values');
        if ~isempty(mvc)
            if numel(mvc)>=1 && mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
            if numel(mvc)>=2 && mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end
        end

        tsec_raw  = (0:numel(emg1_raw)-1)/Fs;
        tsec_filt = (0:numel(filt1)-1)/Fs;

        cla(ax_raw1); hold(ax_raw1,'on');
        plot(ax_raw1,tsec_raw,emg1_raw,'-','Color',color_emg1);
        h = plot(ax_raw1,tsec_raw,emg2_raw,'-','Color',color_emg2);
        setLineAlphaOrLighten(h,color_emg2,alpha_overlay);
        title(ax_raw1,'EMG1 brut'); xlabel(ax_raw1,'Temps (s)'); ylabel(ax_raw1,'Activité (V)');

        cla(ax_raw2); hold(ax_raw2,'on');
        plot(ax_raw2,tsec_raw,emg2_raw,'-','Color',color_emg2);
        h = plot(ax_raw2,tsec_raw,emg1_raw,'-','Color',color_emg1);
        setLineAlphaOrLighten(h,color_emg1,alpha_overlay);
        title(ax_raw2,'EMG2 brut'); xlabel(ax_raw2,'Temps (s)'); ylabel(ax_raw2,'Activité (V)');

        cla(ax_filt1); hold(ax_filt1,'on');
        plot(ax_filt1,tsec_filt,filt1,'-','Color',color_emg1);
        h = plot(ax_filt1,tsec_filt,filt2,'-','Color',color_emg2);
        setLineAlphaOrLighten(h,color_emg2,alpha_overlay);
        title(ax_filt1,'EMG1 filtré (normalisé)'); xlabel(ax_filt1,'Temps (s)'); ylabel(ax_filt1,'(%MVC)');

        cla(ax_filt2); hold(ax_filt2,'on');
        plot(ax_filt2,tsec_filt,filt2,'-','Color',color_emg2);
        h = plot(ax_filt2,tsec_filt,filt1,'-','Color',color_emg1);
        setLineAlphaOrLighten(h,color_emg1,alpha_overlay);
        title(ax_filt2,'EMG2 filtré (normalisé)'); xlabel(ax_filt2,'Temps (s)'); ylabel(ax_filt2,'(%MVC)');

        rec_count = getappdata(fig,'rec_count') + 1;
        setappdata(fig,'rec_count',rec_count);

        recs = getappdata(fig,'recordings_raw');
        recs{rec_count} = rawBuf; %#ok<AGROW>
        setappdata(fig,'recordings_raw',recs);

        assignin('base',sprintf('EMG_recording_raw_%02d',rec_count),rawBuf);
        assignin('base',sprintf('EMG1_filtered_%02d',rec_count),filt1);
        assignin('base',sprintf('EMG2_filtered_%02d',rec_count),filt2);

        assignin('base','EMG_data_raw',rawBuf);
        assignin('base','EMG1_filtered',filt1);
        assignin('base','EMG2_filtered',filt2);
    end
end


function measureMVC(figHandle,mvcTxt,chIdx)
    Fs = getappdata(figHandle,'Fs');
    test_mode = getappdata(figHandle,'test_mode');

    boardNum = getappdata(figHandle,'boardNum');
    gain     = getappdata(figHandle,'gain');

    ch1 = getappdata(figHandle,'chanNum1'); if isempty(ch1), ch1 = 0; end
    ch2 = getappdata(figHandle,'chanNum2'); if isempty(ch2), ch2 = 1; end

    ax_raw1  = getappdata(figHandle,'ax_raw1');
    ax_raw2  = getappdata(figHandle,'ax_raw2');
    ax_filt1 = getappdata(figHandle,'ax_filt1');
    ax_filt2 = getappdata(figHandle,'ax_filt2');

    if chIdx==1
        physCh = ch1; side = 1; targetRaw = ax_raw1; targetFilt = ax_filt1;
    else
        physCh = ch2; side = 2; targetRaw = ax_raw2; targetFilt = ax_filt2;
    end

    durSec = 5;
    nPts = durSec*Fs;

    set(mvcTxt,'String',sprintf('Mesure MVC%d en cours (5 s)...',side)); drawnow;

    if test_mode
        sim = getappdata(figHandle,'sim_data');
        if isempty(sim)
            sim = buildSimData(Fs);
            setappdata(figHandle,'sim_data',sim);
        end
        if side==1, buf = sim.mvc1(:); else, buf = sim.mvc2(:); end
        buf = buf(1:min(nPts,numel(buf)));
    else
        if ~(exist('cbAInScan','file')==2 || exist('cbAInScan','file')==3)
            set(mvcTxt,'String',sprintf('MVC%d impossible: MCC UL manquante.',side));
            return
        end
        buf = acquireOneChannel(boardNum, physCh, gain, Fs, nPts);
    end

    t = (0:numel(buf)-1)/Fs;


    col1 = getappdata(figHandle,'color_emg1');
    col2 = getappdata(figHandle,'color_emg2');
    if side==1, col = col1; else, col = col2; end

    cla(targetRaw); hold(targetRaw,'on');
    plot(targetRaw, t, buf, '-', 'Color', col);
    title(targetRaw,sprintf('EMG%d MVC (%ds)',side,durSec));
    xlabel(targetRaw,'Temps (s)'); ylabel(targetRaw,'Activité (V)');

    env = sqrt(movmean((buf-mean(buf)).^2,100));
    cla(targetFilt); hold(targetFilt,'on');
    plot(targetFilt, t, env, '-', 'Color', col);
    title(targetFilt,sprintf('EMG%d enveloppe MVC',side));
    xlabel(targetFilt,'Temps (s)'); ylabel(targetFilt,'(%MVC)');

    nTake = min(2000,numel(buf));
    topVals = maxk(abs(buf),nTake);
    mvcVal = median(topVals);

    mvc = getappdata(figHandle,'mvc_values'); if isempty(mvc), mvc=[0 0]; end
    mvc(side) = mvcVal;
    setappdata(figHandle,'mvc_values',mvc);

    set(mvcTxt,'String',sprintf('MVC1 = %.2f | MVC2 = %.2f',mvc(1),mvc(2)));
end


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


function sim = buildSimData(Fs)
    rng(1);

    noiseStd = 0.2;
    f_line   = 60;
    lineAmp  = 1.3;

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
