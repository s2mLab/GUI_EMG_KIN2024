function tests = test_EMG_GUI_digilent
% Automated checks for the MATLAB interface without MCC hardware or webcam.
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    testCase.TestData.defaultFigureVisible = get(groot,'DefaultFigureVisible');
    set(groot,'DefaultFigureVisible','off');
    testFolder = fileparts(mfilename('fullpath'));
    testCase.TestData.projectFolder = fileparts(testFolder);
    addpath(testCase.TestData.projectFolder);
end

function teardownOnce(testCase)
    set(groot,'DefaultFigureVisible',testCase.TestData.defaultFigureVisible);
    rmpath(testCase.TestData.projectFolder);
end

function setup(testCase)
    testCase.TestData.figure = EMG_GUI_digilent();
    drawnow;
end

function teardown(testCase)
    if isfield(testCase.TestData,'figure')
        f = testCase.TestData.figure;
        if isgraphics(f)
            delete(f);
        end
    end
end

function testPanelLabelsDoNotOverlapControls(testCase)
    f = testCase.TestData.figure;
    quality = findobj(f,'Tag','qualityTxt');
    exportButton = findobj(f,'Tag','exportCSV');

    rawBounds = renderedBounds(findobj(f,'Tag','ax_raw1'));
    filteredBounds = renderedBounds(findobj(f,'Tag','ax_filt1'));
    frequencyBounds = renderedBounds(findobj(f,'Tag','ax_freq'));

    testCase.verifyLessThan(rawBounds(2) + rawBounds(4), quality.Position(2), ...
        'Le titre EMG superieur recouvre la ligne qualite.');
    testCase.verifyGreaterThan(filteredBounds(2), ...
        exportButton.Position(2) + exportButton.Position(4), ...
        'Le label temporel recouvre les boutons d''export.');
    testCase.verifyGreaterThan(frequencyBounds(2), ...
        exportButton.Position(2) + exportButton.Position(4), ...
        'Le label frequentiel recouvre les boutons d''export.');
end

function testVideoPlaybackControlIsInline(testCase)
    f = testCase.TestData.figure;
    playButton = findobj(f,'Tag','videoPlay');
    slider = findobj(f,'Tag','videoSlider');

    testCase.verifyEqual(playButton.String,'▶');
    testCase.verifyLessThan(playButton.Position(1) + playButton.Position(3), ...
        slider.Position(1), ...
        'Le bouton lecture doit se trouver devant le curseur video.');
    testCase.verifyFalse(startsWith(func2str(slider.Callback),'@('), ...
        'Le curseur video doit utiliser un callback direct MATLAB.');
end

function testNotchFilterIsEnabledByDefault(testCase)
    f = testCase.TestData.figure;
    notchCheck = findobj(f,'Tag','notchCheck');

    testCase.verifyNotEmpty(notchCheck);
    testCase.verifyEqual(notchCheck.Value,1);
    testCase.verifyTrue(getappdata(f,'notch_enabled'));
end

function testSimulationModeDefaultsOffAndIsAtBottomLeft(testCase)
    f = testCase.TestData.figure;
    testCheck = findobj(f,'Tag','testCheck');

    testCase.verifyNotEmpty(testCheck);
    testCase.verifyEqual(testCheck.Style,'checkbox');
    testCase.verifyEqual(testCheck.Value,0);
    testCase.verifyFalse(getappdata(f,'test_mode'));
    testCase.verifyLessThan(testCheck.Position(2),0.10);
end

function testContinuousAnalogBufferStartsIdle(testCase)
    f = testCase.TestData.figure;

    testCase.verifyFalse(getappdata(f,'mcc_continuous_active'));
    testCase.verifyEmpty(getappdata(f,'mcc_continuous_handle'));
    testCase.verifyEqual(getappdata(f,'mcc_continuous_count'),0);
end

function testMvcDynamicScaleTracksSmallSignals(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    axRaw = findobj(f,'Tag','ax_raw1');
    axEnvelope = findobj(f,'Tag','ax_filt1');

    hooks.fitLiveYLimits(axRaw,[-0.012 0.021]);
    hooks.fitLiveYLimits(axEnvelope,[0.0010 0.0012]);

    testCase.verifyLessThan(diff(axRaw.YLim),0.05, ...
        'La MVC brute doit adapter son echelle a une faible amplitude.');
    testCase.verifyLessThan(diff(axEnvelope.YLim),0.001, ...
        'L''enveloppe MVC doit rester lisible pour une faible amplitude.');
end

function testRecordingNoLongerWaitsForPlacementCountdown(testCase)
    f = testCase.TestData.figure;
    previewCheck = findobj(f,'Tag','previewCheck');

    testCase.verifyEmpty(previewCheck, ...
        'L''interface ne doit plus imposer un compte a rebours camera.');
end

function testSignalQualitySuggestsReducingGainOnSaturation(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    raw = repmat([-5; 5],500,2);

    hooks.updateSignalQuality(raw,[],[]);
    qualityText = findobj(f,'Tag','qualityTxt').String;

    testCase.verifyTrue(contains(qualityText,'reduire amplification/gain'));
end

function testSignalQualitySuggestsElectrodeCheckForWeakSignal(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    raw = zeros(1000,2);

    hooks.updateSignalQuality(raw,[],[]);
    qualityText = findobj(f,'Tag','qualityTxt').String;

    testCase.verifyTrue(contains(qualityText,'verifier electrodes et cables'));
end

function testDependencyReportListsInstallableComponents(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    summary = findobj(f,'Tag','dependencySummary');
    report = hooks.dependencyReport();

    testCase.verifyNotEmpty(summary);
    testCase.verifyTrue(contains(report,'Signal Processing Toolbox'));
    testCase.verifyTrue(contains(report,'MccDaq / InstaCal'));
    testCase.verifyTrue(contains(report,'Support Package USB Webcams'));
    testCase.verifyTrue(contains(report,'Capture video parallele winvideo'));
end

function testDisplayModeDefaultsToSignalComparison(testCase)
    f = testCase.TestData.figure;
    displayMode = findobj(f,'Tag','displayMode');

    testCase.verifyNotEmpty(displayMode);
    testCase.verifyEqual(displayMode.Value,2);
    testCase.verifyEqual(getappdata(f,'display_overlay_mode'),'comparison');
end

function testRawFilteredModeOverlaysFilteredSignalsAndSpectra(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    t = (0:2*Fs-1)'/Fs;
    raw = [sin(2*pi*75*t) sin(2*pi*95*t)];
    displayMode = findobj(f,'Tag','displayMode');

    displayMode.Value = 1;
    displayMode.Callback(displayMode,[]);
    hooks.plotFinalAndStore(raw,t,false);

    testCase.verifyEqual(getappdata(f,'display_overlay_mode'),'raw_filtered');
    testCase.verifyNumElements(findobj(f,'Tag','filteredOverlay'),2);
    testCase.verifyNumElements(findobj(f,'Tag','spectrumFiltered'),2);
end

function testRawFilteredModeIsOnlyShownAfterAcquisition(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    displayMode = findobj(f,'Tag','displayMode');

    displayMode.Value = 1;
    displayMode.Callback(displayMode,[]);
    hooks.resetAllAxes('recording');

    testCase.verifyEmpty(findobj(f,'Tag','filteredOverlay'), ...
        'La superposition brut/filtre ne doit pas etre affichee en direct.');
end

function testComparisonModeKeepsTransparentOverlaysAndNamedCursor(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    t = (0:Fs-1)'/Fs;
    raw = [sin(2*pi*40*t) 2*sin(2*pi*60*t)];

    hooks.plotFinalAndStore(raw,t,false);

    testCase.verifyNumElements(findobj(f,'Tag','comparisonOverlay'),4);
    cursor = findobj(f,'Tag','playbackCursor');
    testCase.verifyNumElements(cursor,4);
    testCase.verifyEqual(cursor(1).DisplayName,'Barre du temps');
end

function testPostProcessingScaleIncludesBothComparedSignals(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    raw = zeros(Fs,2);
    raw(round(0.3*Fs),1) = 1.8;
    raw(round(0.7*Fs),2) = -1.5;

    hooks.plotFinalAndStore(raw,(0:Fs-1)'/Fs,false);
    axRaw1 = findobj(f,'Tag','ax_raw1');
    axRaw2 = findobj(f,'Tag','ax_raw2');

    testCase.verifyGreaterThan(axRaw1.YLim(2),1.8);
    testCase.verifyLessThan(axRaw1.YLim(1),-1.5);
    testCase.verifyEqual(axRaw1.YLim,axRaw2.YLim,'AbsTol',1e-12);
end

function testLongTrialMakesOverlayMoreTransparent(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');

    alpha10 = hooks.overlayAlphaForDuration(10);
    alpha30 = hooks.overlayAlphaForDuration(30);

    testCase.verifyLessThan(alpha30,alpha10);
    testCase.verifyEqual(alpha30,alpha10/3,'AbsTol',1e-12);
end

function testVideoTimeSelectsNearestFrame(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    slider = findobj(f,'Tag','videoSlider');

    setappdata(f,'video_frame_times',[0 0.2 0.4 0.6]);
    hooks.setSliderToTime(slider,0.36);

    testCase.verifyEqual(slider.Value,3);
end

function testParallelVideoFrameRateUsesRecordingClockForSynchronization(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    slider = findobj(f,'Tag','videoSlider');

    % A camera may produce 464 frames during an actual 17.2 s recording.
    % They must not be interpreted as 92.6 s because preview is limited to 5 fps.
    frameTimes = hooks.synchronizeVideoFrameTimes(464,0,17.2);
    setappdata(f,'video_frame_times',frameTimes);
    set(slider,'Max',464);
    hooks.setSliderToTime(slider,17.0);

    testCase.verifyEqual(frameTimes(end),17.2,'AbsTol',1e-12);
    testCase.verifyGreaterThan(slider.Value,450, ...
        'Une selection a la fin de l''EMG doit afficher la fin de la video.');
end

function testAcquisitionTimingDelayAddsActionableWarning(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');

    setappdata(f,'last_block_start_time',[]);
    hooks.updateAcquisitionTiming(0,0.1);
    hooks.updateAcquisitionTiming(0.15,0.1);
    hooks.updateSignalQuality(randn(2000,2),[],[]);
    qualityText = findobj(f,'Tag','qualityTxt').String;

    testCase.verifyTrue(contains(qualityText,'Retard acquisition'));
    testCase.verifyTrue(contains(qualityText,'video parallele recommandee'));
end

function testFrequencySpectrumFindsInjectedFrequencies(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    t = (0:4*Fs-1)'/Fs;
    signal1 = sin(2*pi*50*t);
    signal2 = sin(2*pi*120*t);

    [freq1, psd1] = hooks.computePowerSpectrum(signal1,Fs);
    [freq2, psd2] = hooks.computePowerSpectrum(signal2,Fs);
    [~, peak1] = max(psd1);
    [~, peak2] = max(psd2);

    testCase.verifyLessThan(abs(freq1(peak1)-50),2);
    testCase.verifyLessThan(abs(freq2(peak2)-120),2);
end

function testNotchFilterAttenuatesMainsHarmonics(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    t = (0:5*Fs-1)'/Fs;
    keep = (Fs+1):(4*Fs);

    for frequency = [60 120 180 240 300 360]
        signal = sin(2*pi*frequency*t);
        unfiltered = hooks.filterEMG(signal,false);
        filtered = hooks.filterEMG(signal,true);
        testCase.verifyLessThan(mean(filtered(keep)),0.25*mean(unfiltered(keep)), ...
            sprintf('La frequence %d Hz doit etre rejetee.',frequency));
    end

    signal = sin(2*pi*75*t);
    unfiltered = hooks.filterEMG(signal,false);
    filtered = hooks.filterEMG(signal,true);
    testCase.verifyGreaterThan(mean(filtered(keep)),0.75*mean(unfiltered(keep)), ...
        'Le notch ne doit pas supprimer une composante proche non harmonique.');
end

function testNotchToggleRefreshesFilteredFrequencyView(testCase)
    f = testCase.TestData.figure;
    hooks = getappdata(f,'testHooks');
    Fs = getappdata(f,'Fs');
    t = (0:4*Fs-1)'/Fs;
    raw = [sin(2*pi*60*t) sin(2*pi*60*t)];
    displayMode = findobj(f,'Tag','displayMode');
    notchCheck = findobj(f,'Tag','notchCheck');

    displayMode.Value = 1;
    displayMode.Callback(displayMode,[]);
    notchCheck.Value = 0;
    notchCheck.Callback(notchCheck,[]);
    hooks.plotFinalAndStore(raw,t,false);
    before = findobj(f,'Tag','spectrumFiltered');
    beforePeak = max(before(1).YData);

    notchCheck.Value = 1;
    notchCheck.Callback(notchCheck,[]);
    after = findobj(f,'Tag','spectrumFiltered');
    afterPeak = max(after(1).YData);

    testCase.verifyLessThan(afterPeak,beforePeak-3, ...
        'Le changement notch doit recalculer le spectre filtre affiche.');
end

function bounds = renderedBounds(ax)
    pos = ax.Position;
    inset = ax.TightInset;
    bounds = [pos(1)-inset(1), pos(2)-inset(2), ...
        pos(3)+inset(1)+inset(3), pos(4)+inset(2)+inset(4)];
end
