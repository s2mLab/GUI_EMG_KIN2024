#!/usr/bin/env python3
"""PyQtGraph frontend for real-time EMG teaching sessions."""

from __future__ import annotations

import time

import numpy as np
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtWidgets

from EMG_GUI_diligent import (
    CHUNK_PTS,
    FS,
    MIN_MVC_ENV_V,
    MVC_DUR_SEC,
    WINDOW_SEC,
    EMGStreamProcessor,
    MccBackend,
    SimBackend,
    build_sim_data,
    process_emg_offline,
    signal_quality_messages,
)


class EMGRealtimeWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("EMG Acquisition - temps reel PyQtGraph")
        self.resize(1400, 860)

        self.fs = FS
        self.test_mode = True
        self.guided_mode = True
        self.recording = False
        self.mvc = np.zeros(2)
        self.recordings = []
        self.full_blocks = []
        self.display_raw = np.empty((0, 2))
        self.display_env = np.empty((0, 2))
        self.sim = SimBackend(build_sim_data(self.fs))
        self.mcc = MccBackend()
        self.processors = [EMGStreamProcessor(self.fs), EMGStreamProcessor(self.fs)]

        self._build_ui()
        self._update_labels()
        self.timer = QtCore.QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.timer.setInterval(int(1000 * CHUNK_PTS / self.fs))

    def _build_ui(self):
        root = QtWidgets.QWidget()
        self.setCentralWidget(root)
        layout = QtWidgets.QVBoxLayout(root)

        self.guide = QtWidgets.QLabel()
        self.guide.setStyleSheet("font-size: 16px; font-weight: bold; color: #163e78;")
        layout.addWidget(self.guide)

        info_row = QtWidgets.QHBoxLayout()
        self.mode_label = QtWidgets.QLabel()
        self.mvc_label = QtWidgets.QLabel()
        self.quality_label = QtWidgets.QLabel("Qualite : en attente de signal")
        info_row.addWidget(self.mode_label)
        info_row.addStretch()
        info_row.addWidget(self.mvc_label)
        layout.addLayout(info_row)
        layout.addWidget(self.quality_label)

        controls = QtWidgets.QHBoxLayout()
        self.pair = QtWidgets.QComboBox()
        self.pair.addItems([f"AI{k}-AI{k + 1}" for k in range(7)])
        self.pair.currentIndexChanged.connect(lambda _index: self._update_labels())
        self.test_check = QtWidgets.QCheckBox("TEST")
        self.test_check.setChecked(True)
        self.test_check.toggled.connect(self._toggle_test)
        self.guide_check = QtWidgets.QCheckBox("GUIDE")
        self.guide_check.setChecked(True)
        self.guide_check.toggled.connect(self._toggle_guide)
        self.mvc1_btn = QtWidgets.QPushButton("MVC 1")
        self.mvc2_btn = QtWidgets.QPushButton("MVC 2")
        self.record_btn = QtWidgets.QPushButton("Enregistrer")
        self.export_csv_btn = QtWidgets.QPushButton("Exporter CSV")
        self.export_png_btn = QtWidgets.QPushButton("Exporter PNG")
        for button in (self.mvc1_btn, self.mvc2_btn, self.record_btn,
                       self.export_csv_btn, self.export_png_btn):
            button.setMinimumHeight(44)
        self.mvc1_btn.clicked.connect(lambda: self.measure_mvc(1))
        self.mvc2_btn.clicked.connect(lambda: self.measure_mvc(2))
        self.record_btn.clicked.connect(self.toggle_recording)
        self.export_csv_btn.clicked.connect(self.export_csv)
        self.export_png_btn.clicked.connect(self.export_png)
        for widget in (QtWidgets.QLabel("Paire :"), self.pair, self.test_check,
                       self.guide_check, self.mvc1_btn, self.mvc2_btn,
                       self.record_btn, self.export_csv_btn, self.export_png_btn):
            controls.addWidget(widget)
        controls.addStretch()
        layout.addLayout(controls)

        grid = QtWidgets.QGridLayout()
        self.plots = [pg.PlotWidget() for _ in range(4)]
        for idx, plot in enumerate(self.plots):
            plot.showGrid(x=True, y=True, alpha=0.25)
            plot.setLabel("bottom", "Temps", units="s")
            grid.addWidget(plot, idx // 2, idx % 2)
        layout.addLayout(grid)

        self.raw_curves = [
            self.plots[0].plot(pen=pg.mkPen("#0072bd", width=1)),
            self.plots[1].plot(pen=pg.mkPen("#d95319", width=1)),
        ]
        self.env_curves = [
            self.plots[2].plot(pen=pg.mkPen("#0072bd", width=2)),
            self.plots[3].plot(pen=pg.mkPen("#d95319", width=2)),
        ]
        self.raw_overlays = [
            self.plots[0].plot(pen=pg.mkPen((217, 83, 25, 60), width=1)),
            self.plots[1].plot(pen=pg.mkPen((0, 114, 189, 60), width=1)),
        ]
        self.env_overlays = [
            self.plots[2].plot(pen=pg.mkPen((217, 83, 25, 60), width=1)),
            self.plots[3].plot(pen=pg.mkPen((0, 114, 189, 60), width=1)),
        ]

    def _channels(self):
        first = self.pair.currentIndex()
        return first, first + 1

    def _update_labels(self):
        ch1, ch2 = self._channels()
        if self.test_mode:
            mode = "Mode TEST (simule)"
        elif self.mcc.available:
            acquisition = "scan materiel" if self.mcc.scan_enabled else "lecture de secours"
            mode = f"Mode HARDWARE (MCC, {acquisition})"
        else:
            mode = "MCC indisponible - cochez TEST"
        self.mode_label.setText(f"{mode} | paire AI{ch1}-AI{ch2}")
        self.mvc_label.setText(f"MVC1 = {self.mvc[0]:.3f} V | MVC2 = {self.mvc[1]:.3f} V")
        if not self.guided_mode:
            text = "Mode libre : calibrez les MVC avant d'interpreter une valeur en %MVC."
        elif self.mvc[0] <= 0:
            text = "Etape 1/4 - Mesurez MVC 1 pendant une contraction maximale de 5 s."
        elif self.mvc[1] <= 0:
            text = "Etape 2/4 - Mesurez MVC 2 pendant une contraction maximale de 5 s."
        elif not self.recordings:
            text = "Etape 3/4 - Les deux MVC sont pretes : lancez Enregistrer."
        else:
            text = "Etape 4/4 - Interpretez les courbes puis exportez les resultats."
        self.guide.setText(text)

        self.plots[0].setTitle("EMG1 brut")
        self.plots[1].setTitle("EMG2 brut")
        for index, plot in enumerate(self.plots[2:]):
            if self.mvc[index] > 0:
                plot.setTitle(f"EMG{index + 1} enveloppe normalisee")
                plot.setLabel("left", "Activation", units="%MVC")
            else:
                plot.setTitle(f"EMG{index + 1} enveloppe RMS")
                plot.setLabel("left", "Enveloppe RMS", units="V")
        self.plots[0].setLabel("left", "Activite", units="V")
        self.plots[1].setLabel("left", "Activite", units="V")

    def _toggle_test(self, checked):
        if self.recording:
            self.test_check.setChecked(self.test_mode)
            return
        self.test_mode = checked
        if checked:
            self.sim.reset_record()
            self.sim.reset_mvc()
        self._update_labels()

    def _toggle_guide(self, checked):
        self.guided_mode = checked
        self._update_labels()

    def _acquire(self, kind: str, count: int) -> np.ndarray:
        if self.test_mode:
            return self.sim.read_block(kind, count)
        ch1, ch2 = self._channels()
        return self.mcc.read_block(ch1, ch2, count, self.fs)

    def _show_quality(self, raw: np.ndarray, names=None):
        messages = signal_quality_messages(raw, self.fs, names)
        if messages:
            self.quality_label.setStyleSheet("color: #ba271b; font-weight: bold;")
            self.quality_label.setText("Qualite : attention - " + "; ".join(messages))
        else:
            self.quality_label.setStyleSheet("color: #007a3d;")
            self.quality_label.setText("Qualite : signal exploitable")

    def _lock_acquisition_controls(self, locked: bool):
        self.pair.setEnabled(not locked)
        self.test_check.setEnabled(not locked)
        self.guide_check.setEnabled(not locked)
        self.mvc1_btn.setEnabled(not locked)
        self.mvc2_btn.setEnabled(not locked)

    def measure_mvc(self, which: int):
        if self.recording:
            return
        if not self.test_mode and not self.mcc.available:
            self.quality_label.setText("MCC indisponible : activez TEST.")
            return
        if self.test_mode:
            self.sim.reset_mvc()
        processor = EMGStreamProcessor(self.fs)
        raw_parts = []
        env_parts = []
        total = MVC_DUR_SEC * self.fs
        self.guide.setText(f"Mesure MVC {which} en cours : maintenez la contraction 5 s.")
        self._lock_acquisition_controls(True)
        for acquired in range(0, total, CHUNK_PTS):
            block = self._acquire("mvc", min(CHUNK_PTS, total - acquired))
            raw = block[:, which - 1]
            raw_parts.append(raw)
            env_parts.append(processor.process(raw))
            current_raw = np.concatenate(raw_parts)
            current_env = np.concatenate(env_parts)
            t = np.arange(current_raw.size) / self.fs
            self.raw_curves[which - 1].setData(t, current_raw)
            self.env_curves[which - 1].setData(t, current_env)
            QtWidgets.QApplication.processEvents()
            if self.test_mode:
                time.sleep(CHUNK_PTS / self.fs)
        raw = np.concatenate(raw_parts)
        env = np.concatenate(env_parts)
        take = min(self.fs, env.size)
        mvc_value = float(np.median(np.partition(env, -take)[-take:]))
        self._show_quality(raw, [f"EMG{which}"])
        if mvc_value >= MIN_MVC_ENV_V:
            self.mvc[which - 1] = mvc_value
        else:
            self.quality_label.setText(f"MVC{which} insuffisante : recommencez.")
        self._lock_acquisition_controls(False)
        self._update_labels()

    def toggle_recording(self):
        if self.recording:
            self.stop_recording()
            return
        if self.guided_mode and not np.all(self.mvc > 0):
            self.quality_label.setText("Mesurez MVC 1 et MVC 2 avant d'enregistrer en mode GUIDE.")
            return
        if not self.test_mode and not self.mcc.available:
            self.quality_label.setText("MCC indisponible : activez TEST.")
            return
        self.recording = True
        self.full_blocks = []
        self.display_raw = np.empty((0, 2))
        self.display_env = np.empty((0, 2))
        self.processors = [EMGStreamProcessor(self.fs), EMGStreamProcessor(self.fs)]
        for curve in self.raw_overlays + self.env_overlays:
            curve.setData([], [])
        if self.test_mode:
            self.sim.reset_record()
        self.record_btn.setText("Stop")
        self._lock_acquisition_controls(True)
        self.timer.start()

    def _tick(self):
        if not self.recording:
            return
        block = self._acquire("record", CHUNK_PTS)
        self.full_blocks.append(block)
        self.display_raw = np.vstack([self.display_raw, block])[-WINDOW_SEC * self.fs:]
        env = np.column_stack([
            self.processors[0].process(block[:, 0]),
            self.processors[1].process(block[:, 1]),
        ])
        self.display_env = np.vstack([self.display_env, env])[-WINDOW_SEC * self.fs:]
        t = np.arange(-self.display_raw.shape[0], 0) / self.fs
        for index in range(2):
            values = self.display_env[:, index]
            if self.mvc[index] > 0:
                values = 100 * values / self.mvc[index]
            self.raw_curves[index].setData(t, self.display_raw[:, index])
            self.env_curves[index].setData(t, values)

    def stop_recording(self):
        self.timer.stop()
        self.recording = False
        self.record_btn.setText("Enregistrer")
        self._lock_acquisition_controls(False)
        if not self.full_blocks:
            return
        raw = np.vstack(self.full_blocks)
        self.recordings.append(raw)
        self._show_quality(raw)
        self._plot_final(raw)
        self._update_labels()

    def _plot_final(self, raw: np.ndarray):
        t = np.arange(raw.shape[0]) / self.fs
        envelopes = []
        for index in range(2):
            _, env = process_emg_offline(raw[:, index], self.fs)
            if self.mvc[index] > 0:
                env = 100 * env / self.mvc[index]
            envelopes.append(env)
            self.raw_curves[index].setData(t, raw[:, index])
            self.env_curves[index].setData(t, env)
        self.raw_overlays[0].setData(t, raw[:, 1])
        self.raw_overlays[1].setData(t, raw[:, 0])
        self.env_overlays[0].setData(t, envelopes[1])
        self.env_overlays[1].setData(t, envelopes[0])

    def export_csv(self):
        if not self.recordings:
            self.quality_label.setText("Aucun enregistrement a exporter.")
            return
        raw = self.recordings[-1]
        t = np.arange(raw.shape[0]) / self.fs
        env_values = []
        names = []
        for index in range(2):
            _, env = process_emg_offline(raw[:, index], self.fs)
            if self.mvc[index] > 0:
                env = 100 * env / self.mvc[index]
                names.append(f"emg{index + 1}_env_pctMVC")
            else:
                names.append(f"emg{index + 1}_env_V")
            env_values.append(env)
        output = np.column_stack([t, raw, *env_values])
        filename = time.strftime("emg_last_%Y%m%d_%H%M%S.csv")
        header = "time_s,emg1_raw_V,emg2_raw_V," + ",".join(names)
        np.savetxt(filename, output, delimiter=",", header=header, comments="")
        self.quality_label.setText(f"CSV exporte : {filename}")

    def export_png(self):
        filename = time.strftime("emg_graphs_%Y%m%d_%H%M%S.png")
        self.centralWidget().grab().save(filename)
        self.quality_label.setText(f"PNG exporte : {filename}")


def main():
    app = pg.mkQApp("EMG temps reel")
    window = EMGRealtimeWindow()
    window.show()
    app.exec()


if __name__ == "__main__":
    main()
