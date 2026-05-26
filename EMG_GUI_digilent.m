function f = EMG_GUI_digilent()
% EMG GUI — Digilent/MCC (USB-1208FS-PLUS) OR TEST MODE (no hardware)
%
% This version:
% - TEST mode streams at REAL TIME speed using pause() pacing
% - Recording shows RAW (top) + FILTERED+NORMALISED (bottom) LIVE, like MVC
% - MVC streaming uses separate sim index (sim_idx_mvc) from recording (sim_idx_record)

    f = figure('Name','EMG Acquisition pedagogique','NumberTitle','off', ...
        'Position',[100,100,1200,820],'Units','normalized', ...
        'Tag','EMG_GUI_digilent', ...
        'CloseRequestFcn', @onClose);





    %% Colours & constants
    color_emg1 = [0 0.4470 0.7410];
    color_emg2 = [0.8500 0.3250 0.0980];
    alpha_overlay = 0.20;

    Fs = 2000;
    boardNum = 0;

    % MCC .NET is initialised only when hardware mode is requested.
    setappdata(f,'mcc_board',[]);
    setappdata(f,'mcc_range',[]);


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
    setappdata(f,'recordings_time',{});
    setappdata(f,'rawBuf',[]);
    setappdata(f,'timeBuf',[]);
    setappdata(f,'last_plotted_raw',[]);
    setappdata(f,'last_plotted_time',[]);
    setappdata(f,'sampleIdx',0);
    setappdata(f,'test_mode',false);
    setappdata(f,'guided_mode',true);
    setappdata(f,'hardware_scan_enabled',true);
    setappdata(f,'isRecording',false);
    setappdata(f,'isPreparing',false);
    setappdata(f,'notch_enabled',true);
    setappdata(f,'display_overlay_mode','comparison');

    setappdata(f,'sim_data',[]);
    setappdata(f,'sim_idx_record',1);  % record index
    setappdata(f,'sim_idx_mvc',1);     % MVC index (separate!)
    setappdata(f,'recBlinkOn',false);
    setappdata(f,'video_camera',[]);
    setappdata(f,'video_input',[]);
    setappdata(f,'video_backend','none');
    setappdata(f,'video_writer',[]);
    setappdata(f,'video_file','');
    setappdata(f,'video_frame_count',0);
    setappdata(f,'video_fps',10);
    setappdata(f,'video_reader',[]);
    setappdata(f,'video_duration',0);
    setappdata(f,'video_frame_times',[]);
    setappdata(f,'video_trigger_clock',[]);
    setappdata(f,'video_capture_start_time',0);
    setappdata(f,'video_preview_seconds',5);
    setappdata(f,'video_preview_enabled',true);
    setappdata(f,'video_capture_fps',5);
    setappdata(f,'video_next_capture_time',0);
    setappdata(f,'video_display_decimation',2);
    setappdata(f,'video_playback_target_fps',5);
    setappdata(f,'video_playing',false);
    setappdata(f,'playback_cursor_lines',[]);
    setappdata(f,'cursor_max_time',0);
    setappdata(f,'cursor_drag_active',false);
    setappdata(f,'cursor_drag_axis',[]);
    setappdata(f,'last_block_start_time',[]);
    setappdata(f,'max_block_gap_seconds',0);
    setappdata(f,'acquisition_timing_warning','');

    %% Build UI & connect
    buildUI();
    setappdata(f,'sim_data',buildSimData(Fs));
    setappdata(f,'testHooks',struct( ...
        'plotFinalAndStore',@plotFinalAndStore, ...
        'computePowerSpectrum',@computePowerSpectrum, ...
        'preprocessEMG',@(raw,enabled) preprocessEMG(raw,Fs,enabled), ...
        'filterEMG',@(raw,enabled) filterEMG(raw,Fs,enabled), ...
        'updateSignalQuality',@(raw,mvc,channels) updateSignalQuality(f,raw,Fs,mvc,channels), ...
        'dependencyReport',@buildDependencyReport, ...
        'setSliderToTime',@setSliderToTime, ...
        'resetAllAxes',@resetAllAxes, ...
        'updateAcquisitionTiming',@updateAcquisitionTiming));
    connectDAQ();

    % ============================
    % UI BUILD
    % ============================
    function buildUI()
        guideTxt = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.05,0.955,0.90,0.035], ...
            'FontSize',13,'FontWeight','bold','ForegroundColor',[0.08 0.20 0.45], ...
            'HorizontalAlignment','left');
        setappdata(f,'guideTxt',guideTxt);

        % Status + MVC + REC
        statusTxt = uicontrol(f,'Style','text','String','Pret.', ...
            'Units','normalized','Position',[0.05,0.915,0.58,0.035], ...
            'FontSize',12,'HorizontalAlignment','left');
        setappdata(f,'statusTxt',statusTxt);

        recTxt = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.46,0.875,0.10,0.035], ...
            'FontSize',12,'FontWeight','bold','HorizontalAlignment','left', ...
            'ForegroundColor',[1 0 0]);
        setappdata(f,'recTxt',recTxt);

        mvcTxt = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.67,0.915,0.30,0.035], ...
            'FontSize',12,'HorizontalAlignment','left');
        setappdata(f,'mvcTxt',mvcTxt);

        qualityTxt = uicontrol(f,'Style','text','String','Qualite : en attente de signal', ...
            'Units','normalized','Position',[0.05,0.815,0.90,0.035], ...
            'Tag','qualityTxt', ...
            'FontSize',11,'HorizontalAlignment','left', ...
            'ForegroundColor',[0.25 0.25 0.25]);
        setappdata(f,'qualityTxt',qualityTxt);

        % Popup pair
        pairList = arrayfun(@(k) sprintf('AI%d-%d',k,k+1), 0:6, 'UniformOutput', false);
        uicontrol(f,'Style','text','String','Paire EMG:', ...
            'Units','normalized','Position',[0.05,0.875,0.08,0.03],'HorizontalAlignment','left');

        popupPair = uicontrol(f,'Style','popupmenu','String',pairList, ...
            'Units','normalized','Position',[0.13,0.875,0.10,0.035], ...
            'FontSize',11,'Value',1, ...
            'Callback',@(~,~) connectDAQ());
        setappdata(f,'popupPair',popupPair);

        % Axes
        ax_raw1  = axes(f,'Units','normalized','Position',[0.04,0.52,0.29,0.24], ...
            'Tag','ax_raw1'); hold(ax_raw1,'on');
        ax_raw2  = axes(f,'Units','normalized','Position',[0.38,0.52,0.29,0.24], ...
            'Tag','ax_raw2'); hold(ax_raw2,'on');
        ax_filt1 = axes(f,'Units','normalized','Position',[0.04,0.14,0.29,0.25], ...
            'Tag','ax_filt1'); hold(ax_filt1,'on');
        ax_filt2 = axes(f,'Units','normalized','Position',[0.38,0.14,0.29,0.25], ...
            'Tag','ax_filt2'); hold(ax_filt2,'on');

        setappdata(f,'ax_raw1',ax_raw1);
        setappdata(f,'ax_raw2',ax_raw2);
        setappdata(f,'ax_filt1',ax_filt1);
        setappdata(f,'ax_filt2',ax_filt2);

        ax_video = axes(f,'Units','normalized','Position',[0.72,0.52,0.25,0.24], ...
            'Tag','ax_video');
        axis(ax_video,'off');
        title(ax_video,'Webcam');
        setappdata(f,'ax_video',ax_video);
        setappdata(f,'video_image',[]);

        videoPlay = uicontrol(f,'Style','togglebutton','String','▶', ...
            'Units','normalized','Position',[0.72,0.475,0.035,0.034], ...
            'Tag','videoPlay', ...
            'FontSize',14,'FontWeight','bold','Enable','off', ...
            'TooltipString','Lire la video', ...
            'Callback',@(src,~) toggleVideoPlayback(src));
        setappdata(f,'videoPlay',videoPlay);

        videoSlider = uicontrol(f,'Style','slider','Units','normalized', ...
            'Position',[0.762,0.479,0.208,0.026],'Min',1,'Max',2,'Value',1, ...
            'Tag','videoSlider', ...
            'Enable','off','Callback',@seekVideo);
        setappdata(f,'videoSlider',videoSlider);

        videoTxt = uicontrol(f,'Style','text','String','Video : aucune capture', ...
            'Units','normalized','Position',[0.72,0.438,0.25,0.027], ...
            'Tag','videoTxt', ...
            'FontSize',10,'HorizontalAlignment','center');
        setappdata(f,'videoTxt',videoTxt);

        uicontrol(f,'Style','text','String','Apres Stop :', ...
            'Units','normalized','Position',[0.72,0.398,0.085,0.025], ...
            'FontSize',10,'HorizontalAlignment','left');
        displayMode = uicontrol(f,'Style','popupmenu', ...
            'String',{'Brut + filtre','EMG1 + EMG2'}, ...
            'Units','normalized','Position',[0.805,0.397,0.165,0.032], ...
            'FontSize',10,'Value',2,'Tag','displayMode', ...
            'Callback',@(src,~) changeDisplayMode(src));
        setappdata(f,'displayMode',displayMode);

        previewCheck = uicontrol(f,'Style','checkbox','String','Placement camera 5 s', ...
            'Units','normalized','Position',[0.72,0.36,0.25,0.026], ...
            'FontSize',9,'Value',1,'Tag','previewCheck', ...
            'Callback',@(src,~) setappdata(f,'video_preview_enabled',logical(src.Value)));
        setappdata(f,'previewCheck',previewCheck);

        ax_freq = axes(f,'Units','normalized','Position',[0.72,0.14,0.25,0.18], ...
            'Tag','ax_freq');
        hold(ax_freq,'on');
        setappdata(f,'ax_freq',ax_freq);

        % Buttons (top row)
        testCheck = uicontrol(f,'Style','checkbox','String','Mode TEST (simulation)', ...
            'Units','normalized','Position',[0.04,0.02,0.18,0.035],'FontSize',10, ...
            'Tag','testCheck','Value',0, ...
            'Callback',@(src,~) toggleTestMode(src));
        setappdata(f,'testCheck',testCheck);

        uicontrol(f,'Style','pushbutton','String','Bilan installations', ...
            'Units','normalized','Position',[0.235,0.02,0.12,0.035],'FontSize',9, ...
            'Tag','dependencyReportButton','Callback',@(~,~) showDependencyReport());
        dependencySummary = uicontrol(f,'Style','text','String','', ...
            'Units','normalized','Position',[0.365,0.02,0.225,0.035], ...
            'Tag','dependencySummary','FontSize',9,'HorizontalAlignment','left');
        setappdata(f,'dependencySummary',dependencySummary);

        btnGuide = uicontrol(f,'Style','togglebutton','String','GUIDE', ...
            'Units','normalized','Position',[0.25,0.87,0.08,0.045],'FontSize',12, ...
            'Value',1,'Callback',@(src,~) toggleGuidedMode(src));
        setappdata(f,'btnGuide',btnGuide);

        btnStart = uicontrol(f,'Style','togglebutton','String','Enregistrer', ...
            'Units','normalized','Position',[0.61,0.87,0.14,0.045],'FontSize',13, ...
            'Callback',@(src,~) startStopDAQ(src));
        setappdata(f,'btnStart',btnStart);

        notchCheck = uicontrol(f,'Style','checkbox','String','Notch 60 Hz + harmoniques', ...
            'Units','normalized','Position',[0.77,0.875,0.20,0.035], ...
            'FontSize',10,'Value',1,'Tag','notchCheck', ...
            'Callback',@(src,~) toggleNotchFilter(src));
        setappdata(f,'notchCheck',notchCheck);

        uicontrol(f,'Style','pushbutton','String','MVC 1', ...
            'Units','normalized','Position',[0.43,0.87,0.08,0.045],'FontSize',13, ...
            'Callback',@(~,~) measureMVC(1));

        uicontrol(f,'Style','pushbutton','String','MVC 2', ...
            'Units','normalized','Position',[0.52,0.87,0.08,0.045],'FontSize',13, ...
            'Callback',@(~,~) measureMVC(2));

        % Bottom buttons
        uicontrol(f,'Style','pushbutton','String','Exporter les graphiques', ...
            'Units','normalized','Position',[0.60,0.02,0.18,0.035],'FontSize',12, ...
            'Tag','exportGraphs', ...
            'Callback',@(~,~) exportGraphs(f,ax_raw1,ax_raw2,ax_filt1,ax_filt2,ax_freq));

        uicontrol(f,'Style','pushbutton','String','Exporter CSV', ...
            'Units','normalized','Position',[0.80,0.02,0.18,0.035],'FontSize',12, ...
            'Tag','exportCSV', ...
            'Callback',@(~,~) exportCSV(f));

        % Initial axes labels/titles + create live lines
        resetAllAxes('idle');
        updateGuide();
        updateDependencySummary();
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
        displayMode = getappdata(f,'displayMode');

        if isempty(popupPair) || ~isvalid(popupPair), return, end

        switch state
            case 'idle'
                set(popupPair,'Enable','on');
                if ~isempty(displayMode) && isvalid(displayMode)
                    set(displayMode,'Enable','on');
                end
                if ~isempty(btnStart) && isvalid(btnStart)
                    btnStart.Value = 0;
                    btnStart.String = 'Enregistrer';
                end
                if ~isempty(recTxt) && isvalid(recTxt)
                    set(recTxt,'String','');
                end
                setappdata(f,'recBlinkOn',false);

            case 'recording'
                set(popupPair,'Enable','off');
                if ~isempty(displayMode) && isvalid(displayMode)
                    set(displayMode,'Enable','off');
                end
                if ~isempty(btnStart) && isvalid(btnStart)
                    btnStart.String = 'Stop';
                end
                if ~isempty(recTxt) && isvalid(recTxt)
                    set(recTxt,'String','REC');
                end
                setappdata(f,'recBlinkOn',true);

            case 'mvc'
                set(popupPair,'Enable','off');
                if ~isempty(displayMode) && isvalid(displayMode)
                    set(displayMode,'Enable','off');
                end
        end
    end

    function resetAllAxes(context)
        ax_raw1  = getappdata(f,'ax_raw1');
        ax_raw2  = getappdata(f,'ax_raw2');
        ax_filt1 = getappdata(f,'ax_filt1');
        ax_filt2 = getappdata(f,'ax_filt2');
        ax_freq  = getappdata(f,'ax_freq');

        setappdata(f,'playback_cursor_lines',[]);
        setappdata(f,'cursor_drag_active',false);
        setappdata(f,'cursor_drag_axis',[]);
        set(f,'WindowButtonMotionFcn','','WindowButtonUpFcn','');
        set([ax_raw1 ax_raw2 ax_filt1 ax_filt2],'ButtonDownFcn','');

        cla(ax_raw1);  hold(ax_raw1,'on');
        cla(ax_raw2);  hold(ax_raw2,'on');
        cla(ax_filt1); hold(ax_filt1,'on');
        cla(ax_filt2); hold(ax_filt2,'on');
        cla(ax_freq);  hold(ax_freq,'on');

        applyAxisStyle(ax_raw1,  'EMG1 brut', color_emg1, 'Activité (V)');
        applyAxisStyle(ax_raw2,  'EMG2 brut', color_emg2, 'Activité (V)');
        styleEnvelopeAxis(ax_filt1, 1, color_emg1);
        styleEnvelopeAxis(ax_filt2, 2, color_emg2);
        title(ax_freq,'Analyse frequentielle');
        xlabel(ax_freq,'Frequence (Hz)');
        ylabel(ax_freq,'DSP (dB/Hz)');
        xlim(ax_freq,[0 500]);
        grid(ax_freq,'on');
        hideAxesToolbar([ax_raw1 ax_raw2 ax_filt1 ax_filt2 ax_freq]);

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

    function styleEnvelopeAxis(ax, which, col)
        mvc = getappdata(f,'mvc_values');
        if ~isempty(mvc) && numel(mvc)>=which && mvc(which)>0
            applyAxisStyle(ax, sprintf('EMG%d enveloppe normalisee',which), col, 'Activation (%MVC)');
        else
            applyAxisStyle(ax, sprintf('EMG%d enveloppe RMS',which), col, 'Enveloppe RMS (V)');
        end
    end

    function updateGuide()
        guideTxt = getappdata(f,'guideTxt');
        if isempty(guideTxt) || ~isvalid(guideTxt), return, end
        mvc = getappdata(f,'mvc_values');
        recs = getappdata(f,'recordings_raw');
        if ~getappdata(f,'guided_mode')
            msg = 'Mode libre : calibrez les MVC avant d''interpreter une valeur en %MVC.';
        elseif isempty(mvc) || mvc(1)<=0
            msg = 'Etape 1/4 - Mesurez MVC 1 pendant une contraction maximale de 5 s.';
        elseif mvc(2)<=0
            msg = 'Etape 2/4 - Mesurez MVC 2 pendant une contraction maximale de 5 s.';
        elseif isempty(recs)
            msg = 'Etape 3/4 - Les deux MVC sont pretes : lancez Enregistrer.';
        else
            msg = 'Etape 4/4 - Interpretez les courbes puis exportez les resultats.';
        end
        set(guideTxt,'String',msg);
    end

    function blinkREC()
        recTxt = getappdata(f,'recTxt');
        if isempty(recTxt) || ~isvalid(recTxt), return, end
        blink = getappdata(f,'recBlinkOn');
        if blink
            set(recTxt,'String','');
        else
            set(recTxt,'String','REC');
        end
        setappdata(f,'recBlinkOn',~blink);
    end

    function showVideoFrame(frame)
        axVideo = getappdata(f,'ax_video');
        hImage = getappdata(f,'video_image');
        if isempty(hImage) || ~isvalid(hImage)
            axes(axVideo); %#ok<LAXES>
            hImage = image(axVideo, frame);
            axis(axVideo,'image');
            axis(axVideo,'off');
            title(axVideo,'Webcam');
            setappdata(f,'video_image',hImage);
        else
            set(hImage,'CData',frame);
        end
    end

    function hasVideo = prepareVideoCapture()
        stopVideoPlayback();
        setappdata(f,'video_file','');
        setappdata(f,'video_frame_count',0);
        setappdata(f,'video_reader',[]);
        setappdata(f,'video_duration',0);
        setappdata(f,'video_frame_times',[]);
        setappdata(f,'video_trigger_clock',[]);
        setappdata(f,'video_capture_start_time',0);
        setappdata(f,'video_input',[]);
        setappdata(f,'video_backend','none');
        videoSlider = getappdata(f,'videoSlider');
        videoPlay = getappdata(f,'videoPlay');
        set(videoSlider,'Enable','off','Value',1);
        set(videoPlay,'Enable','off','Value',0,'String','▶','TooltipString','Lire la video');
        cam = [];
        hasVideo = false;
        if ~getappdata(f,'video_preview_enabled') && hasParallelVideoAdaptor()
            setappdata(f,'video_backend','imaq');
            set(getappdata(f,'videoTxt'),'String','Video : capture parallele sans apercu');
            hasVideo = true;
            return
        end
        if exist('webcam','file') ~= 2 && exist('webcam','class') ~= 8
            setappdata(f,'video_camera',[]);
            setappdata(f,'video_writer',[]);
            set(getappdata(f,'videoTxt'),'String','Video : webcam indisponible');
            setStatus('EMG actif; webcam indisponible (support package requis).', [0.75 0.35 0]);
            return
        end
        try
            cam = webcam;
            setappdata(f,'video_camera',cam);
            setappdata(f,'video_writer',[]);
            previewSeconds = 0;
            if getappdata(f,'video_preview_enabled')
                previewSeconds = getappdata(f,'video_preview_seconds');
            end
            countdown = tic;
            while ishandle(f) && getappdata(f,'isPreparing') && toc(countdown) < previewSeconds
                frame = snapshot(cam);
                showVideoFrame(frame);
                remaining = max(0,ceil(previewSeconds - toc(countdown)));
                set(getappdata(f,'videoTxt'),'String', ...
                    sprintf('Positionnement : depart dans %d s',remaining));
                setStatus('Placez-vous devant la camera; depart automatique imminent.', [0.2 0.2 0.2]);
                drawnow limitrate;
                pause(0.05);
            end
            hasVideo = ishandle(f);
            if hasVideo && hasParallelVideoAdaptor()
                setappdata(f,'video_camera',[]);
                clear cam
                setappdata(f,'video_backend','imaq');
                set(getappdata(f,'videoTxt'),'String','Video : capture parallele prete');
            else
                setappdata(f,'video_backend','webcam');
                set(getappdata(f,'videoTxt'),'String','Video : repli webcam, risque retard EMG');
            end
        catch ME
            clear cam
            setappdata(f,'video_camera',[]);
            setappdata(f,'video_writer',[]);
            setStatus('EMG actif; webcam indisponible (support package requis).', [0.75 0.35 0]);
            disp(getReport(ME,'extended'));
        end
    end

    function toggleNotchFilter(src)
        enabled = logical(get(src,'Value'));
        setappdata(f,'notch_enabled',enabled);
        if enabled
            setStatus('Filtre notch actif : 60 Hz et harmoniques.', [0.2 0.2 0.2]);
        else
            setStatus('Filtre notch desactive : bruit secteur conserve.', [0.75 0.35 0]);
        end
        refreshLastProcessedView();
    end

    function changeDisplayMode(src)
        if get(src,'Value') == 1
            setappdata(f,'display_overlay_mode','raw_filtered');
            setStatus('Affichage apres arret : brut transparent et filtre.', [0.2 0.2 0.2]);
        else
            setappdata(f,'display_overlay_mode','comparison');
            setStatus('Affichage : comparaison EMG1 et EMG2.', [0.2 0.2 0.2]);
        end
        refreshLastProcessedView();
    end

    function refreshLastProcessedView()
        if getappdata(f,'isRecording'), return, end
        rawBuf = getappdata(f,'last_plotted_raw');
        timeBuf = getappdata(f,'last_plotted_time');
        if ~isempty(rawBuf) && ~isempty(timeBuf)
            plotFinalAndStore(rawBuf,timeBuf,false);
        end
    end

    function hideAxesToolbar(axesList)
        for k = 1:numel(axesList)
            try
                axesList(k).Toolbar.Visible = 'off';
            catch
                % Toolbar control is unavailable on older MATLAB releases.
            end
        end
    end

    function startTriggeredVideoCapture(hasVideo)
        if ~hasVideo
            setappdata(f,'video_trigger_clock',tic);
            return
        end
        vid = [];
        try
            if strcmp(getappdata(f,'video_backend'),'imaq')
                filename = ['emg_video_' datestr(now,'yyyymmdd_HHMMSS') '.avi'];
                writer = VideoWriter(filename,'Motion JPEG AVI');
                writer.FrameRate = getappdata(f,'video_capture_fps');
                vid = videoinput('winvideo',1);
                vid.LoggingMode = 'disk';
                vid.FramesPerTrigger = Inf;
                vid.DiskLogger = writer;
                setappdata(f,'video_input',vid);
                setappdata(f,'video_writer',[]);
                setappdata(f,'video_file',filename);
                setappdata(f,'video_trigger_clock',tic);
                start(vid);
                setappdata(f,'video_capture_start_time',toc(getappdata(f,'video_trigger_clock')));
                set(getappdata(f,'videoTxt'),'String','Video : capture parallele en cours');
                return
            end
            filename = ['emg_video_' datestr(now,'yyyymmdd_HHMMSS') '.mp4'];
            writer = VideoWriter(filename,'MPEG-4');
            writer.FrameRate = getappdata(f,'video_capture_fps');
            open(writer);
            setappdata(f,'video_writer',writer);
            setappdata(f,'video_file',filename);
            setappdata(f,'video_frame_count',0);
            setappdata(f,'video_frame_times',[]);
            setappdata(f,'video_next_capture_time',0);
            setappdata(f,'video_trigger_clock',tic);
            set(getappdata(f,'videoTxt'),'String','Video : capture webcam horodatee');
        catch ME
            if ~isempty(vid), try delete(vid); catch, end, end
            setappdata(f,'video_input',[]);
            setappdata(f,'video_writer',[]);
            setappdata(f,'video_camera',[]);
            setappdata(f,'video_trigger_clock',tic);
            setStatus('EMG actif; demarrage video impossible.', [0.75 0.35 0]);
            disp(getReport(ME,'extended'));
        end
    end

    function captureVideoFrame()
        if strcmp(getappdata(f,'video_backend'),'imaq')
            return
        end
        cam = getappdata(f,'video_camera');
        writer = getappdata(f,'video_writer');
        if isempty(cam) || isempty(writer), return, end
        try
            triggerClock = getappdata(f,'video_trigger_clock');
            beforeSnapshot = toc(triggerClock);
            if beforeSnapshot < getappdata(f,'video_next_capture_time')
                return
            end
            frame = snapshot(cam);
            frameTime = 0.5 * (beforeSnapshot + toc(triggerClock));
            writeVideo(writer,frame);
            setappdata(f,'video_frame_count',getappdata(f,'video_frame_count') + 1);
            frameTimes = getappdata(f,'video_frame_times');
            setappdata(f,'video_frame_times',[frameTimes frameTime]);
            setappdata(f,'video_next_capture_time',frameTime + 1/getappdata(f,'video_capture_fps'));
        catch ME
            setStatus('Capture webcam interrompue; acquisition EMG maintenue.', [0.75 0.35 0]);
            disp(getReport(ME,'extended'));
        end
    end

    function stopVideoCapture()
        vid = getappdata(f,'video_input');
        if ~isempty(vid)
            try
                stop(vid);
                frameCount = double(vid.FramesAcquired);
                fps = max(getappdata(f,'video_capture_fps'),1);
                t0 = getappdata(f,'video_capture_start_time');
                if frameCount > 0
                    setappdata(f,'video_frame_times',t0 + (0:frameCount-1)/fps);
                end
                delete(vid);
            catch ME
                disp(getReport(ME,'extended'));
            end
        end
        setappdata(f,'video_input',[]);
        writer = getappdata(f,'video_writer');
        if ~isempty(writer)
            try close(writer); catch, end
        end
        setappdata(f,'video_writer',[]);
        setappdata(f,'video_camera',[]);
        filename = getappdata(f,'video_file');
        if isempty(filename) || ~isfile(filename), return, end
        try
            reader = VideoReader(filename);
            frameTimes = getappdata(f,'video_frame_times');
            if isempty(frameTimes)
                frameCount = max(1,floor(reader.Duration * reader.FrameRate));
                frameTimes = (0:frameCount-1) / max(reader.FrameRate,1);
                setappdata(f,'video_frame_times',frameTimes);
            else
                frameCount = numel(frameTimes);
            end
            setappdata(f,'video_reader',reader);
            setappdata(f,'video_frame_count',frameCount);
            setappdata(f,'video_fps',reader.FrameRate);
            setappdata(f,'video_duration',frameTimes(end));
            slider = getappdata(f,'videoSlider');
            step = 1 / max(frameCount - 1, 1);
            set(slider,'Min',1,'Max',max(2,frameCount),'Value',1, ...
                'SliderStep',[step min(1,10*step)],'Enable','on');
            set(getappdata(f,'videoPlay'),'Enable','on','Value',0,'String','▶', ...
                'TooltipString','Lire la video');
            seekVideo(slider);
        catch ME
            set(getappdata(f,'videoTxt'),'String','Video : fichier illisible');
            disp(getReport(ME,'extended'));
        end
    end

    function seekVideo(slider,varargin) %#ok<INUSD>
        filename = getappdata(f,'video_file');
        if isempty(filename) || ~isfile(filename), return, end
        frameIndex = round(get(slider,'Value'));
        frameTimes = getappdata(f,'video_frame_times');
        if isempty(frameTimes), return, end
        frameIndex = max(1,min(frameIndex, numel(frameTimes)));
        fps = max(getappdata(f,'video_fps'),1);
        signalTime = frameTimes(frameIndex);
        mediaTime = (frameIndex-1) / fps;
        displayVideoAtTime(mediaTime,signalTime);
        updatePlaybackCursor(signalTime);
    end

    function displayVideoAtTime(mediaTime,signalTime)
        reader = getappdata(f,'video_reader');
        filename = getappdata(f,'video_file');
        if isempty(reader)
            reader = VideoReader(filename);
            setappdata(f,'video_reader',reader);
        end
        duration = max(0, getappdata(f,'video_duration'));
        reader.CurrentTime = min(max(0,mediaTime), ...
            max(0, reader.Duration - 1/max(reader.FrameRate,1)));
        if hasFrame(reader)
            frame = readFrame(reader);
            step = max(1,round(getappdata(f,'video_display_decimation')));
            showVideoFrame(frame(1:step:end,1:step:end,:));
        end
        set(getappdata(f,'videoTxt'),'String', ...
            sprintf('Video sync : %.2f / %.2f s',signalTime,duration));
    end

    function toggleVideoPlayback(src)
        if src.Value == 0
            set(src,'String','▶','TooltipString','Lire la video');
            setappdata(f,'video_playing',false);
            return
        end
        set(src,'String','❚❚','TooltipString','Mettre en pause');
        setappdata(f,'video_playing',true);
        slider = getappdata(f,'videoSlider');
        frameTimes = getappdata(f,'video_frame_times');
        displayInterval = 1 / max(getappdata(f,'video_playback_target_fps'),1);
        while ishandle(f) && getappdata(f,'video_playing') && src.Value == 1
            currentFrame = round(get(slider,'Value'));
            targetTime = frameTimes(currentFrame) + displayInterval;
            nextFrame = find(frameTimes >= targetTime,1,'first');
            if isempty(nextFrame)
                src.Value = 0;
                break
            end
            set(slider,'Value',nextFrame);
            seekVideo(slider);
            drawnow;
            pause(max(0,frameTimes(nextFrame)-frameTimes(currentFrame)));
        end
        if ishandle(src)
            set(src,'String','▶','TooltipString','Lire la video','Value',0);
        end
        setappdata(f,'video_playing',false);
    end

    function stopVideoPlayback()
        setappdata(f,'video_playing',false);
        videoPlay = getappdata(f,'videoPlay');
        if ~isempty(videoPlay) && isvalid(videoPlay)
            set(videoPlay,'Value',0,'String','▶','TooltipString','Lire la video');
        end
    end

    function available = hasParallelVideoAdaptor()
        available = false;
        if exist('videoinput','file') ~= 2
            return
        end
        try
            info = imaqhwinfo;
            available = any(strcmpi(info.InstalledAdaptors,'winvideo'));
        catch
            available = false;
        end
    end

    function updateDependencySummary()
        summary = getappdata(f,'dependencySummary');
        if isempty(summary) || ~isvalid(summary), return, end
        availability = assessDependencies();
        missing = {};
        if ~availability.signalProcessing, missing{end+1} = 'Signal Toolbox'; end %#ok<AGROW>
        if ~availability.mcc, missing{end+1} = 'MCC'; end %#ok<AGROW>
        if ~availability.webcam, missing{end+1} = 'Webcam'; end %#ok<AGROW>
        if ~availability.parallelVideo, missing{end+1} = 'Video parallele'; end %#ok<AGROW>
        if isempty(missing)
            text = 'Installation : complete';
            col = [0 0.45 0.20];
        else
            text = ['A installer : ' strjoin(missing, ', ')];
            col = [0.75 0.35 0];
        end
        set(summary,'String',text,'ForegroundColor',col, ...
            'TooltipString',buildDependencyReport());
    end

    function showDependencyReport()
        msgbox(buildDependencyReport(),'Bilan des installations MATLAB','help');
    end

    function report = buildDependencyReport()
        availability = assessDependencies();
        lines = {'Bilan des composants disponibles :'};
        lines{end+1} = dependencyLine(availability.signalProcessing, ...
            'Signal Processing Toolbox', ...
            'installer Signal Processing Toolbox pour le filtrage et le spectre');
        lines{end+1} = dependencyLine(availability.mcc, ...
            'MccDaq / InstaCal', ...
            'installer Universal Library et configurer la carte avec InstaCal');
        lines{end+1} = dependencyLine(availability.webcam, ...
            'Support Package USB Webcams', ...
            'installer MATLAB Support Package for USB Webcams');
        lines{end+1} = dependencyLine(availability.parallelVideo, ...
            'Capture video parallele winvideo', ...
            'installer Image Acquisition Toolbox et OS Generic Video Interface');
        report = strjoin(lines,newline);
    end

    function availability = assessDependencies()
        availability.signalProcessing = exist('butter','file') == 2 && ...
            exist('filtfilt','file') == 2 && exist('pwelch','file') == 2;
        availability.mcc = ~isempty(getappdata(f,'mcc_board'));
        availability.webcam = exist('webcam','file') == 2 || exist('webcam','class') == 8;
        availability.parallelVideo = hasParallelVideoAdaptor();
    end

    function text = dependencyLine(isAvailable,name,installAction)
        if isAvailable
            text = ['[OK] ' name];
        else
            text = ['[MANQUANT] ' name ' : ' installAction '.'];
        end
    end

    function installPlaybackCursor()
        axesList = [getappdata(f,'ax_raw1'), getappdata(f,'ax_raw2'), ...
            getappdata(f,'ax_filt1'), getappdata(f,'ax_filt2')];
        cursorLines = gobjects(1,numel(axesList));
        for k = 1:numel(axesList)
            ax = axesList(k);
            set(ax,'ButtonDownFcn',@selectCursorFromAxis);
            children = findobj(ax,'Type','line');
            set(children,'HitTest','off','PickableParts','none');
            yl = ylim(ax);
            cursorLines(k) = line(ax,[0 0],yl,'Color',[0.85 0.10 0.10], ...
                'LineWidth',1.5,'HitTest','on','PickableParts','all', ...
                'ButtonDownFcn',@startCursorDrag);
        end
        setappdata(f,'playback_cursor_lines',cursorLines);
        updatePlaybackCursor(0);
    end

    function selectCursorFromAxis(src,~)
        previewCursorTime(src.CurrentPoint(1,1));
        setappdata(f,'cursor_drag_axis',src);
        setappdata(f,'cursor_drag_active',true);
        set(f,'WindowButtonMotionFcn',@dragPlaybackCursor, ...
            'WindowButtonUpFcn',@stopCursorDrag);
    end

    function startCursorDrag(src,~)
        ax = ancestor(src,'axes');
        previewCursorTime(ax.CurrentPoint(1,1));
        setappdata(f,'cursor_drag_axis',ax);
        setappdata(f,'cursor_drag_active',true);
        set(f,'WindowButtonMotionFcn',@dragPlaybackCursor, ...
            'WindowButtonUpFcn',@stopCursorDrag);
    end

    function dragPlaybackCursor(~,~)
        if ~getappdata(f,'cursor_drag_active'), return, end
        ax = getappdata(f,'cursor_drag_axis');
        if isempty(ax) || ~isvalid(ax), return, end
        previewCursorTime(ax.CurrentPoint(1,1));
    end

    function stopCursorDrag(~,~)
        ax = getappdata(f,'cursor_drag_axis');
        setappdata(f,'cursor_drag_active',false);
        set(f,'WindowButtonMotionFcn','','WindowButtonUpFcn','');
        if ~isempty(ax) && isvalid(ax)
            moveCursorToTime(ax.CurrentPoint(1,1));
        end
    end

    function moveCursorToTime(timeSec)
        timeSec = max(0,min(timeSec,getappdata(f,'cursor_max_time')));
        slider = getappdata(f,'videoSlider');
        if ~isempty(slider) && isvalid(slider) && strcmp(get(slider,'Enable'),'on')
            setSliderToTime(slider,timeSec);
            seekVideo(slider);
        else
            updatePlaybackCursor(timeSec);
        end
    end

    function previewCursorTime(timeSec)
        timeSec = max(0,min(timeSec,getappdata(f,'cursor_max_time')));
        updatePlaybackCursor(timeSec);
        slider = getappdata(f,'videoSlider');
        if ~isempty(slider) && isvalid(slider) && strcmp(get(slider,'Enable'),'on')
            setSliderToTime(slider,timeSec);
            seekVideo(slider);
        end
    end

    function setSliderToTime(slider,timeSec)
        frameTimes = getappdata(f,'video_frame_times');
        if isempty(frameTimes), return, end
        [~,frameIndex] = min(abs(frameTimes - timeSec));
        set(slider,'Value',frameIndex);
    end

    function updatePlaybackCursor(timeSec)
        cursorLines = getappdata(f,'playback_cursor_lines');
        if isempty(cursorLines), return, end
        timeSec = max(0,min(timeSec,getappdata(f,'cursor_max_time')));
        for k = 1:numel(cursorLines)
            if isvalid(cursorLines(k))
                set(cursorLines(k),'XData',[timeSec timeSec]);
            end
        end
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
            updateDependencySummary();
            updateGuide();
            return
        end

        try
            if isempty(getappdata(f,'mcc_board'))
                assemblyPath = load_mccdaq_assembly();
                setappdata(f,'mcc_assembly_path',assemblyPath);
                setappdata(f,'mcc_board',MccDaq.MccBoard(getappdata(f,'boardNum')));
                setappdata(f,'mcc_range',MccDaq.Range.Bip5Volts);
            end
            mcc_board = getappdata(f,'mcc_board');
            mcc_range = getappdata(f,'mcc_range');
        
            [err1, raw1] = mcc_board.AIn(int32(ch1), mcc_range);
            [err2, raw2] = mcc_board.AIn(int32(ch2), mcc_range);
        
            if int32(err1.Value)~=0 || int32(err2.Value)~=0
                error(formatMccError('AIn', err1, err2));
            end
        
            % juste pour valider conversion possible
            mcc_board.ToEngUnits(mcc_range, raw1);
            mcc_board.ToEngUnits(mcc_range, raw2);
        
            setStatus(sprintf('MCC détectée (.NET) | paire AI%d-%d',ch1,ch2), 'green');
        catch ME
            if contains(ME.message, 'CB.CFG') || contains(ME.message, '126')
                setStatus('CB.CFG absent : ouvrez InstaCal et configurez la carte 0.', 'red');
            else
                setStatus('Erreur MCC (.NET). Consultez la console ou activez TEST.', 'red');
            end
            disp(getReport(ME,'extended'));
        end
        updateDependencySummary();

    end

    function msg = formatMccError(operation, err1, err2)
        value1 = int32(err1.Value);
        value2 = int32(err2.Value);
        details = sprintf('%s: err1=%d (%s) err2=%d (%s).', operation, ...
            value1, char(err1.Message), value2, char(err2.Message));
        if value1 == 126 || value2 == 126
            msg = [details ' Fichier CB.CFG introuvable. Lancez InstaCal, ' ...
                'ajoutez la carte MCC et assignez-la au numero 0.'];
        else
            msg = details;
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
            setappdata(f,'hardware_scan_enabled',true);
            setappdata(f,'sim_data',[]);
            setappdata(f,'sim_idx_record',1);
            setappdata(f,'sim_idx_mvc',1);
            setStatus('Mode TEST désactivé.',[0.2 0.2 0.2]);
        end
        connectDAQ();
        updateGuide();
    end

    function toggleGuidedMode(src)
        setappdata(f,'guided_mode',logical(src.Value));
        updateGuide();
    end

    function [ch1, ch2] = getSelectedPair()
        popupPair = getappdata(f,'popupPair');
        pairIdx = get(popupPair,'Value'); % 1..7 => AI0-1..AI6-7
        ch1 = pairIdx - 1;
        ch2 = ch1 + 1;
    end

    function block = mccReadBlock(board, range, ch1, ch2, nPts, Fs)
        block = zeros(nPts,2);
        t0 = tic;
        for k = 1:nPts
            [err1, raw1] = board.AIn(int32(ch1), range);
            [err2, raw2] = board.AIn(int32(ch2), range);
            if int32(err1.Value)~=0 || int32(err2.Value)~=0
                error(formatMccError('AIn', err1, err2));
            end

            [~, v1]   = board.ToEngUnits(range, raw1);
            [~, v2]   = board.ToEngUnits(range, raw2);
    
            block(k,:) = [double(v1), double(v2)];
    
            % pacing ~ Fs
            target = k/Fs;
            dt = toc(t0);
            if dt < target
                pause(target - dt);
            end
        end
    end

    function block = mccReadBlockScan(board, range, ch1, ch2, nPts, Fs)
        count = int32(nPts * 2);
        memHandle = MccDaq.MccService.ScaledWinBufAllocEx(count);
        if memHandle.ToInt64() == int64(0)
            error('Impossible d''allouer le tampon MCC.');
        end
        cleanup = onCleanup(@() MccDaq.MccService.WinBufFreeEx(memHandle));
        rate = int32(Fs);
        err = board.AInScan(int32(ch1), int32(ch2), count, rate, range, ...
            memHandle, MccDaq.ScanOptions.ScaleData);
        if int32(err.Value) ~= 0
            if int32(err.Value) == 126
                error(['AInScan: err=126 (%s). Fichier CB.CFG introuvable. ' ...
                    'Lancez InstaCal, ajoutez la carte MCC et assignez-la au numero 0.'], ...
                    char(err.Message));
            end
            error('Erreur MCC AInScan: err=%d (%s)', int32(err.Value), char(err.Message));
        end
        values = NET.createArray('System.Double', double(count));
        err = MccDaq.MccService.ScaledWinBufToArray(memHandle, values, int32(0), count);
        if int32(err.Value) ~= 0
            error('Erreur MCC ScaledWinBufToArray: err=%d', int32(err.Value));
        end
        block = reshape(double(values), 2, nPts)';
        clear cleanup
    end



    % ============================
    % RECORDING (START/STOP)
    % ============================
    function startStopDAQ(src)
        test_mode = getappdata(f,'test_mode');

        if src.Value
            % START
            mvc = getappdata(f,'mvc_values');
            if getappdata(f,'guided_mode') && (isempty(mvc) || any(mvc<=0))
                src.Value = 0;
                setStatus('Mesurez MVC 1 et MVC 2 avant d''enregistrer en mode GUIDE.', 'red');
                updateGuide();
                return
            end
            setappdata(f,'isPreparing',true);
            set(src,'String','Annuler');
            hasVideo = prepareVideoCapture();
            setappdata(f,'isPreparing',false);
            if ~ishandle(f), return, end
            if src.Value == 0
                stopVideoCapture();
                setUIState('idle');
                setStatus('Preparation annulee.', [0.2 0.2 0.2]);
                return
            end
            setappdata(f,'rawBuf',zeros(getappdata(f,'Fs')*60,2));
            setappdata(f,'timeBuf',zeros(getappdata(f,'Fs')*60,1));
            setappdata(f,'sampleIdx',0);
            setappdata(f,'last_block_start_time',[]);
            setappdata(f,'max_block_gap_seconds',0);
            setappdata(f,'acquisition_timing_warning','');
            setappdata(f,'isRecording',true);

            if test_mode
                setappdata(f,'sim_idx_record',1);
            end

            resetAllAxes('recording');
            setUIState('recording');
            startTriggeredVideoCapture(hasVideo);

            try
                streamRecording();
            catch ME
                setappdata(f,'isRecording',false);
                setUIState('idle');
                stopVideoCapture();
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
            if getappdata(f,'isPreparing')
                setappdata(f,'isPreparing',false);
                return
            end
            setappdata(f,'isRecording',false);
            setUIState('idle');
            stopVideoCapture();

            rawBuf = getappdata(f,'rawBuf');
            rawBuf = rawBuf(1:getappdata(f,'sampleIdx'),:);
            setappdata(f,'rawBuf',rawBuf);
            timeBuf = getappdata(f,'timeBuf');
            timeBuf = timeBuf(1:getappdata(f,'sampleIdx'));
            setappdata(f,'timeBuf',timeBuf);
            updateSignalQuality(f, rawBuf, getappdata(f,'Fs'), [], []);
            if isempty(rawBuf)
                return
            end

            plotFinalAndStore(rawBuf,timeBuf);
        end
    end

    function streamRecording()
        Fs = getappdata(f,'Fs');
        windowPts = Fs*5;
        if getappdata(f,'test_mode')
            chunkPts = 200;
        else
            chunkPts = 400;
        end
        chunkSec = chunkPts / Fs;

        while getappdata(f,'isRecording') && ishandle(f)
            loopTic = tic;

            rawBuf    = getappdata(f,'rawBuf');
            timeBuf   = getappdata(f,'timeBuf');
            sampleIdx = getappdata(f,'sampleIdx');

            triggerClock = getappdata(f,'video_trigger_clock');
            blockStart = toc(triggerClock);
            updateAcquisitionTiming(blockStart,chunkSec);
            block = acquireBlockUnified('record', chunkPts); % Nx2
            captureVideoFrame();
            N = size(block,1);
            blockTimes = blockStart + (0:N-1)'/Fs;
            neededPts = sampleIdx + N;
            if neededPts > size(rawBuf,1)
                rawBuf = [rawBuf; zeros(Fs*60,2)]; %#ok<AGROW>
                timeBuf = [timeBuf; zeros(Fs*60,1)]; %#ok<AGROW>
            end
            rawBuf(sampleIdx+1:neededPts,:) = block;
            timeBuf(sampleIdx+1:neededPts) = blockTimes;
            setappdata(f,'rawBuf',rawBuf);
            setappdata(f,'timeBuf',timeBuf);

            sampleIdx = neededPts;
            setappdata(f,'sampleIdx',sampleIdx);

            totalPts = sampleIdx;
            if totalPts <= windowPts
                idx = 1:totalPts;
            else
                idx = (totalPts-windowPts+1):totalPts;
            end

            tsec = timeBuf(idx);

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

            filt1 = filterEMG(ch1win, Fs, getappdata(f,'notch_enabled'));
            filt2 = filterEMG(ch2win, Fs, getappdata(f,'notch_enabled'));

            if mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
            if mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end

            hf1 = getappdata(f,'hLine_filt1');
            hf2 = getappdata(f,'hLine_filt2');
            if ~isempty(hf1) && isvalid(hf1), set(hf1,'XData',tsec,'YData',filt1,'Color',color_emg1); end
            if ~isempty(hf2) && isvalid(hf2), set(hf2,'XData',tsec,'YData',filt2,'Color',color_emg2); end
            fitLiveYLimits(getappdata(f,'ax_raw1'),ch1win);
            fitLiveYLimits(getappdata(f,'ax_raw2'),ch2win);
            fitLiveYLimits(getappdata(f,'ax_filt1'),filt1);
            fitLiveYLimits(getappdata(f,'ax_filt2'),filt2);
            if ~isempty(tsec)
                xWindow = [max(0,tsec(end)-5), max(5,tsec(end))];
                set([getappdata(f,'ax_raw1') getappdata(f,'ax_raw2') ...
                    getappdata(f,'ax_filt1') getappdata(f,'ax_filt2')],'XLim',xWindow);
            end
            if sampleIdx >= Fs && mod(sampleIdx,Fs) < N
                updateSignalQuality(f,[ch1win ch2win],Fs,[],[]);
            end

            blinkREC();
            drawnow limitrate;

            if getappdata(f,'test_mode')
                elapsed = toc(loopTic);
                pause(max(0, chunkSec - elapsed));
            end
        end
    end

    function updateAcquisitionTiming(blockStart,chunkSec)
        previousStart = getappdata(f,'last_block_start_time');
        setappdata(f,'last_block_start_time',blockStart);
        if isempty(previousStart), return, end
        gap = blockStart - previousStart - chunkSec;
        if gap > getappdata(f,'max_block_gap_seconds')
            setappdata(f,'max_block_gap_seconds',gap);
        end
        if gap > 0.020
            message = sprintf('Retard acquisition %.0f ms : video parallele recommandee.',1000*gap);
            setappdata(f,'acquisition_timing_warning',message);
        end
    end

    function plotFinalAndStore(rawBuf,timeBuf,shouldStore)
        if nargin < 3
            shouldStore = true;
        end
        Fs = getappdata(f,'Fs');
        mvc = getappdata(f,'mvc_values');
        setappdata(f,'last_plotted_raw',rawBuf);
        setappdata(f,'last_plotted_time',timeBuf);

        emg1_raw = rawBuf(:,1);
        emg2_raw = rawBuf(:,2);

        filteredSignal1 = preprocessEMG(emg1_raw, Fs, getappdata(f,'notch_enabled'));
        filteredSignal2 = preprocessEMG(emg2_raw, Fs, getappdata(f,'notch_enabled'));
        filt1 = filterEMG(emg1_raw, Fs, getappdata(f,'notch_enabled'));
        filt2 = filterEMG(emg2_raw, Fs, getappdata(f,'notch_enabled'));

        if ~isempty(mvc)
            if numel(mvc)>=1 && mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
            if numel(mvc)>=2 && mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end
        end

        tsec_raw  = timeBuf(:)';
        tsec_filt = tsec_raw;

        ax_raw1  = getappdata(f,'ax_raw1');
        ax_raw2  = getappdata(f,'ax_raw2');
        ax_filt1 = getappdata(f,'ax_filt1');
        ax_filt2 = getappdata(f,'ax_filt2');
        ax_freq  = getappdata(f,'ax_freq');
        overlayMode = getappdata(f,'display_overlay_mode');

        cla(ax_raw1); hold(ax_raw1,'on');
        if strcmp(overlayMode,'raw_filtered')
            h = plot(ax_raw1, tsec_raw, emg1_raw, '-', 'Color', color_emg1, ...
                'DisplayName','EMG1 brut','Tag','rawOverlay');
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
            plot(ax_raw1, tsec_raw, filteredSignal1, '-', 'Color', color_emg1, ...
                'LineWidth',1.1,'DisplayName','EMG1 filtre','Tag','filteredOverlay');
            applyAxisStyle(ax_raw1,'EMG1 brut + filtre', color_emg1, 'Activite (V)');
            legend(ax_raw1,'show','Location','best');
        else
            plot(ax_raw1, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
            h = plot(ax_raw1, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
            applyAxisStyle(ax_raw1,'EMG1 brut', color_emg1, 'Activite (V)');
        end
        set(ax_raw1,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_raw2); hold(ax_raw2,'on');
        if strcmp(overlayMode,'raw_filtered')
            h = plot(ax_raw2, tsec_raw, emg2_raw, '-', 'Color', color_emg2, ...
                'DisplayName','EMG2 brut','Tag','rawOverlay');
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
            plot(ax_raw2, tsec_raw, filteredSignal2, '-', 'Color', color_emg2, ...
                'LineWidth',1.1,'DisplayName','EMG2 filtre','Tag','filteredOverlay');
            applyAxisStyle(ax_raw2,'EMG2 brut + filtre', color_emg2, 'Activite (V)');
            legend(ax_raw2,'show','Location','best');
        else
            plot(ax_raw2, tsec_raw, emg2_raw, '-', 'Color', color_emg2);
            h = plot(ax_raw2, tsec_raw, emg1_raw, '-', 'Color', color_emg1);
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
            applyAxisStyle(ax_raw2,'EMG2 brut', color_emg2, 'Activite (V)');
        end
        set(ax_raw2,'XLim',[tsec_raw(1) tsec_raw(end)]);

        cla(ax_filt1); hold(ax_filt1,'on');
        plot(ax_filt1, tsec_filt, filt1, '-', 'Color', color_emg1);
        if strcmp(overlayMode,'comparison')
            h = plot(ax_filt1, tsec_filt, filt2, '-', 'Color', color_emg2);
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
        end
        styleEnvelopeAxis(ax_filt1, 1, color_emg1);
        set(ax_filt1,'XLim',[tsec_filt(1) tsec_filt(end)]);

        cla(ax_filt2); hold(ax_filt2,'on');
        plot(ax_filt2, tsec_filt, filt2, '-', 'Color', color_emg2);
        if strcmp(overlayMode,'comparison')
            h = plot(ax_filt2, tsec_filt, filt1, '-', 'Color', color_emg1);
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
        end
        styleEnvelopeAxis(ax_filt2, 2, color_emg2);
        set(ax_filt2,'XLim',[tsec_filt(1) tsec_filt(end)]);

        [freq1, psd1] = computePowerSpectrum(emg1_raw, Fs);
        [freq2, psd2] = computePowerSpectrum(emg2_raw, Fs);
        cla(ax_freq); hold(ax_freq,'on');
        if strcmp(overlayMode,'raw_filtered')
            h = plot(ax_freq,freq1,psd1,'-','Color',color_emg1,'DisplayName','EMG1 brut');
            setLineAlphaOrLighten(h, color_emg1, alpha_overlay);
            h = plot(ax_freq,freq2,psd2,'-','Color',color_emg2,'DisplayName','EMG2 brut');
            setLineAlphaOrLighten(h, color_emg2, alpha_overlay);
            [freqFilt1, psdFilt1] = computePowerSpectrum(filteredSignal1, Fs);
            [freqFilt2, psdFilt2] = computePowerSpectrum(filteredSignal2, Fs);
            plot(ax_freq,freqFilt1,psdFilt1,'-','Color',color_emg1, ...
                'LineWidth',1.1,'DisplayName','EMG1 filtre','Tag','spectrumFiltered');
            plot(ax_freq,freqFilt2,psdFilt2,'-','Color',color_emg2, ...
                'LineWidth',1.1,'DisplayName','EMG2 filtre','Tag','spectrumFiltered');
        else
            plot(ax_freq,freq1,psd1,'-','Color',color_emg1,'DisplayName','EMG1');
            plot(ax_freq,freq2,psd2,'-','Color',color_emg2,'DisplayName','EMG2');
        end
        title(ax_freq,'Analyse frequentielle');
        xlabel(ax_freq,'Frequence (Hz)');
        ylabel(ax_freq,'DSP (dB/Hz)');
        xlim(ax_freq,[0 min(500,Fs/2)]);
        grid(ax_freq,'on');
        legend(ax_freq,'Location','best');

        setappdata(f,'cursor_max_time',tsec_raw(end));
        installPlaybackCursor();

        if ~shouldStore
            return
        end

        rec_count = getappdata(f,'rec_count') + 1;
        setappdata(f,'rec_count',rec_count);

        recs = getappdata(f,'recordings_raw');
        recs{rec_count} = rawBuf; %#ok<AGROW>
        setappdata(f,'recordings_raw',recs);
        recTimes = getappdata(f,'recordings_time');
        recTimes{rec_count} = timeBuf; %#ok<AGROW>
        setappdata(f,'recordings_time',recTimes);

        assignin('base',sprintf('EMG_recording_raw_%02d',rec_count),rawBuf);
        assignin('base',sprintf('EMG_recording_time_%02d',rec_count),timeBuf);
        assignin('base',sprintf('EMG1_filtered_%02d',rec_count),filt1);
        assignin('base',sprintf('EMG2_filtered_%02d',rec_count),filt2);

        assignin('base','EMG_data_raw',rawBuf);
        assignin('base','EMG_time_s',timeBuf);
        assignin('base','EMG1_filtered',filt1);
        assignin('base','EMG2_filtered',filt2);

        setStatus(sprintf('Enregistrement #%02d sauvegardé.', rec_count), [0.2 0.2 0.2]);
        updateGuide();
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
        applyAxisStyle(targetFilt, sprintf('EMG%d enveloppe MVC',whichMVC),      col, 'Enveloppe RMS (V)');
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

                env = filterEMG(buf, Fs, getappdata(f,'notch_enabled'));
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

        envMVC = filterEMG(buf, Fs, getappdata(f,'notch_enabled'));
        nTake = min(2000,numel(envMVC));
        topVals = maxk(envMVC,nTake);
        mvcVal = median(topVals);
        if mvcVal < 0.01
            setUIState('idle');
            setStatus(sprintf('MVC%d insuffisante : recommencez la mesure.',whichMVC), 'red');
            updateSignalQuality(figHandle, buf, Fs, mvcVal, whichMVC);
            return
        end

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
        updateGuide();

        updateSignalQuality(figHandle, buf, Fs, mvcVal, whichMVC);
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
            mcc_board = getappdata(f,'mcc_board');
            mcc_range = getappdata(f,'mcc_range');
            ch1 = getappdata(f,'chanNum1');
            ch2 = getappdata(f,'chanNum2');
        
            if getappdata(f,'hardware_scan_enabled')
                try
                    block = mccReadBlockScan(mcc_board, mcc_range, ch1, ch2, nPts, Fs);
                    return
                catch ME
                    setappdata(f,'hardware_scan_enabled',false);
                    setStatus('Scan MCC indisponible : lecture de secours active.', [0.75 0.35 0]);
                    disp(getReport(ME,'extended'));
                end
            end
            block = mccReadBlock(mcc_board, mcc_range, ch1, ch2, nPts, Fs);
        end
    end

    % ============================
    % CLOSE
    % ============================
    function onClose(~,~)
        setappdata(f,'isRecording',false);
        try stopVideoPlayback(); catch, end
        try stopVideoCapture(); catch, end
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
function emg = preprocessEMG(raw, Fs, notchEnabled)
    if nargin < 3
        notchEnabled = true;
    end
    raw = raw - mean(raw);

    emg_notch = raw;
    if notchEnabled
        maxNotchFrequency = min(400,Fs/2-2);
        notchFrequencies = 60:60:maxNotchFrequency;
        halfWidthHz = 1;
        for f0 = notchFrequencies
            if exist('iirnotch','file') == 2
                wo = f0/(Fs/2);
                bw = (2*halfWidthHz)/(Fs/2);
                [b,a] = iirnotch(wo,bw);
                emg_notch = filtfilt(b,a,emg_notch);
            else
                d = designfilt('bandstopiir', ...
                    'FilterOrder',2, ...
                    'HalfPowerFrequency1',f0-halfWidthHz, ...
                    'HalfPowerFrequency2',f0+halfWidthHz, ...
                    'SampleRate',Fs);
                emg_notch = filtfilt(d,emg_notch);
            end
        end
    end

    [b,a] = butter(4,[20 400]/(Fs/2),'bandpass');
    emg = filtfilt(b,a,emg_notch);
end

function filtered = filterEMG(raw, Fs, notchEnabled)
    if nargin < 3
        notchEnabled = true;
    end
    emg = preprocessEMG(raw, Fs, notchEnabled);
    filtered = sqrt(movmean(emg.^2,100));
end

function fitLiveYLimits(ax,data)
    data = data(isfinite(data));
    if isempty(data), return, end
    low = min(data);
    high = max(data);
    span = high-low;
    if span <= eps
        span = max(abs(low),1) * 0.2;
    end
    padding = max(0.05*span,eps);
    set(ax,'YLim',[low-padding high+padding]);
end

function [freq, psdDb] = computePowerSpectrum(raw, Fs)
    x = double(raw(:));
    x = x - mean(x);
    if numel(x) < 2
        freq = 0;
        psdDb = NaN;
        return
    end

    windowLength = min(numel(x), max(256,round(Fs)));
    nfft = max(1024,2^nextpow2(windowLength));
    if exist('pwelch','file') == 2 && windowLength >= 8
        [psd, freq] = pwelch(x,windowLength,floor(windowLength/2),nfft,Fs);
    else
        spectrum = fft(x,nfft);
        keep = 1:(floor(nfft/2)+1);
        freq = (keep-1)' * Fs / nfft;
        psd = abs(spectrum(keep)).^2 / (Fs*numel(x));
        psd = psd(:);
    end
    psdDb = 10*log10(max(psd,eps));
end

% =========================================================================
% EXPORTS
% =========================================================================
function exportGraphs(figHandle, ax_raw1,ax_raw2,ax_filt1,ax_filt2,ax_freq)
    fig = figure('Visible','off','Position',[100,100,1200,1000]);
    subplot(3,2,1); copyobj(allchild(ax_raw1), gca);
    title(ax_raw1.Title.String); xlabel('Temps (s)'); ylabel(ax_raw1.YLabel.String);
    subplot(3,2,2); copyobj(allchild(ax_raw2), gca);
    title(ax_raw2.Title.String); xlabel('Temps (s)'); ylabel(ax_raw2.YLabel.String);
    mvc = getappdata(figHandle,'mvc_values');
    subplot(3,2,3); copyobj(allchild(ax_filt1), gca);
    if ~isempty(mvc) && mvc(1)>0
        title('EMG1 enveloppe normalisee'); ylabel('Activation (%MVC)');
    else
        title('EMG1 enveloppe RMS'); ylabel('Enveloppe RMS (V)');
    end
    xlabel('Temps (s)');
    subplot(3,2,4); copyobj(allchild(ax_filt2), gca);
    if ~isempty(mvc) && mvc(2)>0
        title('EMG2 enveloppe normalisee'); ylabel('Activation (%MVC)');
    else
        title('EMG2 enveloppe RMS'); ylabel('Enveloppe RMS (V)');
    end
    xlabel('Temps (s)');
    subplot(3,2,[5 6]); copyobj(allchild(ax_freq), gca);
    title('Analyse frequentielle'); xlabel('Frequence (Hz)'); ylabel('DSP (dB/Hz)');
    xlim([0 min(500,getappdata(figHandle,'Fs')/2)]);
    grid on;
    legend(gca,'show','Location','best');

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
    recTimes = getappdata(figHandle,'recordings_time');
    emg1_raw = rawBuf(:,1);
    emg2_raw = rawBuf(:,2);

    filt1 = filterEMG(emg1_raw, Fs, getappdata(figHandle,'notch_enabled'));
    filt2 = filterEMG(emg2_raw, Fs, getappdata(figHandle,'notch_enabled'));

    mvc = getappdata(figHandle,'mvc_values');
    if ~isempty(mvc)
        if numel(mvc)>=1 && mvc(1)>0, filt1 = 100*(filt1/mvc(1)); end
        if numel(mvc)>=2 && mvc(2)>0, filt2 = 100*(filt2/mvc(2)); end
    end

    env1Name = 'emg1_env_V';
    env2Name = 'emg2_env_V';
    if ~isempty(mvc) && numel(mvc)>=1 && mvc(1)>0, env1Name = 'emg1_env_pctMVC'; end
    if ~isempty(mvc) && numel(mvc)>=2 && mvc(2)>0, env2Name = 'emg2_env_pctMVC'; end
    if isempty(recTimes) || numel(recTimes) < numel(recs) || isempty(recTimes{end})
        t = (0:size(rawBuf,1)-1)'/Fs;
    else
        t = recTimes{end};
    end
    T = table(t, emg1_raw, emg2_raw, filt1, filt2, ...
        'VariableNames', {'time_s','emg1_raw_V','emg2_raw_V',env1Name,env2Name});

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


function updateSignalQuality(figHandle, rawBuf, Fs, mvcValue, channelNumbers)
% Reports saturation, weak signals, mains interference and insufficient MVC.
    if isempty(rawBuf) || ~isnumeric(rawBuf)
        return
    end

    messages = {};
    satMask = any(abs(rawBuf) >= 4.90, 2);
    satPct  = 100 * (sum(satMask) / size(rawBuf,1));
    if satPct > 0.5
        messages{end+1} = sprintf('saturation %.1f%% : reduire amplification/gain',satPct); %#ok<AGROW>
    end

    for channel = 1:size(rawBuf,2)
        if isempty(channelNumbers)
            channelNumber = channel;
        else
            channelNumber = channelNumbers(channel);
        end
        x = rawBuf(:,channel) - mean(rawBuf(:,channel));
        if std(x) < 0.005
            messages{end+1} = sprintf('EMG%d faible : verifier electrodes et cables',channelNumber); %#ok<AGROW>
            continue
        end
        if numel(x) >= Fs
            n = numel(x);
            power = abs(fft(x)).^2;
            freq = (0:n-1)' * Fs / n;
            bandPower = sum(power(freq>=20 & freq<=400));
            linePower = sum(power(freq>=59 & freq<=61));
            if bandPower > 0 && linePower / bandPower > 0.25
                messages{end+1} = sprintf('EMG%d bruit 60 Hz : verifier masse et alimentation',channelNumber); %#ok<AGROW>
            end
        end
    end

    if ~isempty(mvcValue) && mvcValue < 0.01
        messages{end+1} = 'MVC faible : refaire une contraction maximale'; %#ok<AGROW>
    end
    timingWarning = getappdata(figHandle,'acquisition_timing_warning');
    if ~isempty(timingWarning)
        messages{end+1} = timingWarning; %#ok<AGROW>
    end

    qualityTxt = getappdata(figHandle,'qualityTxt');
    if isempty(qualityTxt) || ~isvalid(qualityTxt)
        return
    end
    if isempty(messages)
        set(qualityTxt,'String','Qualite : signal exploitable', ...
            'ForegroundColor',[0 0.45 0.20]);
    else
        set(qualityTxt,'String',['Qualite : attention - ' strjoin(messages,'; ')], ...
            'ForegroundColor',[0.75 0.10 0.05]);
    end
end
