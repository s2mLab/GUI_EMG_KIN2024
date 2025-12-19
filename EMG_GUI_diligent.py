# emg_gui_digilent.py
# Python translation of the provided MATLAB script (structure + behaviour).
#
# GUI: PyQt6 + pyqtgraph
# Filtering: scipy.signal (notch 60Hz + bandpass 20-400Hz) + RMS envelope
# Test mode: simulated data with separate indices for record vs MVC (like MATLAB version)

from __future__ import annotations

import sys
import time
from dataclasses import dataclass

import numpy as np
from PyQt5 import QtCore, QtWidgets
import pyqtgraph as pg
from scipy.signal import iirnotch, butter, filtfilt

from mcculw import ul
from mcculw.enums import ULRange, ScanOptions
from mcculw.ul import ULError



# ============================
# SIMULATION GENERATOR
# ============================
@dataclass
class SimData:
    Fs: int
    tMVC: np.ndarray
    mvc1: np.ndarray
    mvc2: np.ndarray
    tRec: np.ndarray
    rec1: np.ndarray
    rec2: np.ndarray


def build_sim_data(Fs: int) -> SimData:
    rng = np.random.default_rng(1)

    noise_std = 0.2
    f_line = 60.0
    line_amp = 0.3

    # MVC 5s: ramp 1s, hold 3s, rest 1s
    dur_mvc = 5.0
    Nmvc = int(dur_mvc * Fs)
    tMVC = np.arange(Nmvc) / Fs

    env = np.zeros(Nmvc)
    env[:Fs] = np.linspace(0, 1, Fs)                      # ramp 1s
    env[Fs:Fs + 3 * Fs] = 1                               # hold 3s
    env[Fs + 3 * Fs:Fs + 4 * Fs] = 0                      # rest 1s

    A1, A2 = 2.0, 3.0
    mvc1 = (A1 * env) * rng.standard_normal(Nmvc) + noise_std * rng.standard_normal(Nmvc)
    mvc2 = (A2 * env) * rng.standard_normal(Nmvc) + noise_std * rng.standard_normal(Nmvc) \
           + line_amp * np.sin(2 * np.pi * f_line * tMVC)

    mvc1 -= mvc1.mean()
    mvc2 -= mvc2.mean()

    # Recording 5s
    dur_rec = 5.0
    Nrec = int(dur_rec * Fs)
    tRec = np.arange(Nrec) / Fs

    rec1 = noise_std * rng.standard_normal(Nrec)
    rec2 = noise_std * rng.standard_normal(Nrec) + line_amp * np.sin(2 * np.pi * f_line * tRec)

    # Muscle1 bursts: two 1.5V bursts, 1s each
    burstA1 = 1.5
    nb1 = int(1.0 * Fs)
    starts1 = (np.array([1.0, 3.0]) * Fs).astype(int)
    car1 = rng.standard_normal(Nrec)
    for s in starts1:
        idx = np.arange(s + 1, s + 1 + nb1)
        idx = idx[idx < Nrec]
        rec1[idx] += burstA1 * car1[idx]

    # Muscle2 bursts: four 0.5V bursts, 0.7s each
    burstA2 = 0.5
    nb2 = int(0.7 * Fs)
    starts2 = (np.array([0.6, 1.7, 2.8, 3.9]) * Fs).astype(int)
    car2 = rng.standard_normal(Nrec)
    for s in starts2:
        idx = np.arange(s + 1, s + 1 + nb2)
        idx = idx[idx < Nrec]
        rec2[idx] += burstA2 * car2[idx]

    rec1 -= rec1.mean()
    rec2 -= rec2.mean()

    return SimData(Fs=Fs, tMVC=tMVC, mvc1=mvc1, mvc2=mvc2, tRec=tRec, rec1=rec1, rec2=rec2)


# ============================
# FILTERING
# ============================
def rms_envelope(x: np.ndarray, win: int = 100) -> np.ndarray:
    # centred-ish moving RMS (simple causal/zero-phase not required for display)
    x0 = x - x.mean()
    x2 = x0 * x0
    kernel = np.ones(win) / win
    m = np.convolve(x2, kernel, mode="same")
    return np.sqrt(np.maximum(m, 0.0))


def filter_emg(raw: np.ndarray, Fs: int) -> np.ndarray:
    raw = raw - raw.mean()

    # Notch 60 Hz
    f0 = 60.0
    Q = 2.0
    w0 = f0 / (Fs / 2.0)
    b_notch, a_notch = iirnotch(w0, Q)
    emg_notch = filtfilt(b_notch, a_notch, raw)

    # Bandpass 20–400 Hz
    b_bp, a_bp = butter(4, [20 / (Fs / 2.0), 400 / (Fs / 2.0)], btype="bandpass")
    emg = filtfilt(b_bp, a_bp, emg_notch)

    # Envelope RMS
    return rms_envelope(emg, win=100)


# ============================
# HARDWARE ACQUISITION (STUB)
# ============================
class HardwareDAQ:
    """
    MCC Universal Library (mcculw) backend.
    Requires MCC DAQ Software + InstaCal.
    """

    def __init__(self, board_num: int = 0, ul_range=ULRange.BIP10VOLTS):
        self.board_num = board_num
        self.ul_range = ul_range

    def test_read(self, ch: int) -> None:
        # Single read to confirm the board + channel works
        try:
            _ = ul.a_in(self.board_num, ch, self.ul_range)
        except ULError as e:
            raise RuntimeError(f"UL test_read failed on ch{ch}: {e}") from e

    def read_block(self, ch1: int, ch2: int, n_pts: int, Fs: int) -> tuple[np.ndarray, np.ndarray]:
        """
        Acquire n_pts samples from ch1..ch2 (inclusive).
        Returns (v1, v2) in volts.
        """
        low_chan = min(ch1, ch2)
        high_chan = max(ch1, ch2)
        n_ch = high_chan - low_chan + 1

        total_count = n_pts * n_ch

        memhandle = ul.win_buf_alloc(total_count)
        if memhandle == 0:
            raise RuntimeError("win_buf_alloc failed")

        try:
            # Blocking scan (like cbAInScan)
            ul.a_in_scan(
                self.board_num,
                low_chan,
                high_chan,
                total_count,
                Fs,
                self.ul_range,
                memhandle,
                ScanOptions.DEFAULT
            )

            counts = np.array(ul.win_buf_to_array(memhandle, total_count), dtype=np.int32)

            # Convert counts -> volts
            volts = np.empty_like(counts, dtype=float)
            for i, c in enumerate(counts):
                volts[i] = ul.to_eng_units(self.board_num, self.ul_range, int(c))

            # Deinterleave: UL returns interleaved samples by channel
            volts = volts.reshape(-1, n_ch)          # shape: (n_pts, n_ch)
            v1 = volts[:, (ch1 - low_chan)]
            v2 = volts[:, (ch2 - low_chan)]
            return v1, v2

        except ULError as e:
            raise RuntimeError(f"UL scan failed: {e}") from e
        finally:
            ul.win_buf_free(memhandle)


# ============================
# GUI
# ============================
class EMGGui(QtWidgets.QWidget):
    def __init__(self):
        super().__init__()

        # constants/state
        self.Fs = 2000
        self.board_num = 0

        self.color_emg1 = (0, 114, 189)    # approx MATLAB default blue
        self.color_emg2 = (217, 83, 25)    # approx MATLAB default orange
        self.alpha_overlay = 0.20

        self.mvc_values = np.array([0.0, 0.0], dtype=float)
        self.rec_count = 0
        self.recordings_raw: list[np.ndarray] = []

        self.test_mode = False
        self.is_recording = False

        self.sim_data: SimData | None = None
        self.sim_idx_record = 0
        self.sim_idx_mvc = 0

        self.chunk_pts = 200
        self.window_sec = 5.0
        self.window_pts = int(self.window_sec * self.Fs)
        self.chunk_sec = self.chunk_pts / self.Fs

        self.raw_buf = np.empty((0, 2), dtype=float)

        # hardware (optional)
        self.hw: HardwareDAQ | None = HardwareDAQ(board_num=self.board_num, ul_range=ULRange.BIP5VOLTS)


        # timer for streaming loop
        self.timer = QtCore.QTimer(self)
        self.timer.timeout.connect(self._on_timer_tick)
        self._last_tick = None
        self._blink = False

        self._build_ui()
        self._connect_daq()

    # ---------- UI ----------
    def _build_ui(self):
        self.setWindowTitle("EMG Acquisition")

        # top bar
        self.status_lbl = QtWidgets.QLabel("Prêt. Activez 🧪 Test si pas de carte.")
        self.rec_lbl = QtWidgets.QLabel("")
        self.rec_lbl.setStyleSheet("color: red; font-weight: bold;")
        self.mvc_lbl = QtWidgets.QLabel("")

        # pair popup
        pair_list = [f"AI{k}-{k+1}" for k in range(0, 7)]
        self.pair_combo = QtWidgets.QComboBox()
        self.pair_combo.addItems(pair_list)
        self.pair_combo.currentIndexChanged.connect(self._connect_daq)

        # buttons
        self.btn_test = QtWidgets.QPushButton("🧪 Test")
        self.btn_test.setCheckable(True)
        self.btn_test.clicked.connect(self._toggle_test_mode)

        self.btn_record = QtWidgets.QPushButton("⏺ Enregistrer")
        self.btn_record.setCheckable(True)
        self.btn_record.clicked.connect(self._start_stop_record)

        self.btn_mvc1 = QtWidgets.QPushButton("MVC 1")
        self.btn_mvc1.clicked.connect(lambda: self._measure_mvc(1))

        self.btn_mvc2 = QtWidgets.QPushButton("MVC 2")
        self.btn_mvc2.clicked.connect(lambda: self._measure_mvc(2))

        self.btn_export_png = QtWidgets.QPushButton("Exporter les graphiques")
        self.btn_export_png.clicked.connect(self._export_png)

        self.btn_export_csv = QtWidgets.QPushButton("Exporter CSV")
        self.btn_export_csv.clicked.connect(self._export_csv)

        # plots (2x2)
        pg.setConfigOptions(antialias=True)
        self.p_raw1 = pg.PlotWidget()
        self.p_raw2 = pg.PlotWidget()
        self.p_filt1 = pg.PlotWidget()
        self.p_filt2 = pg.PlotWidget()

        self._reset_axes(context="idle")

        # layout
        top_row = QtWidgets.QHBoxLayout()
        top_row.addWidget(self.status_lbl, 6)
        top_row.addWidget(self.rec_lbl, 2)
        top_row.addWidget(self.mvc_lbl, 4)

        ctrl_row = QtWidgets.QHBoxLayout()
        ctrl_row.addWidget(QtWidgets.QLabel("Paire EMG:"))
        ctrl_row.addWidget(self.pair_combo)
        ctrl_row.addSpacing(20)
        ctrl_row.addWidget(self.btn_test)
        ctrl_row.addWidget(self.btn_record)
        ctrl_row.addWidget(self.btn_mvc1)
        ctrl_row.addWidget(self.btn_mvc2)
        ctrl_row.addStretch(1)

        grid = QtWidgets.QGridLayout()
        grid.addWidget(self.p_raw1, 0, 0)
        grid.addWidget(self.p_raw2, 0, 1)
        grid.addWidget(self.p_filt1, 1, 0)
        grid.addWidget(self.p_filt2, 1, 1)

        bottom_row = QtWidgets.QHBoxLayout()
        bottom_row.addStretch(1)
        bottom_row.addWidget(self.btn_export_png)
        bottom_row.addWidget(self.btn_export_csv)

        layout = QtWidgets.QVBoxLayout(self)
        layout.addLayout(top_row)
        layout.addLayout(ctrl_row)
        layout.addLayout(grid)
        layout.addLayout(bottom_row)

    def _set_status(self, msg: str, color: str | None = None):
        self.status_lbl.setText(msg)
        if color is not None:
            self.status_lbl.setStyleSheet(f"color: {color};")
        else:
            self.status_lbl.setStyleSheet("")

    def _set_ui_state(self, state: str):
        if state == "idle":
            self.pair_combo.setEnabled(True)
            self.btn_record.setChecked(False)
            self.btn_record.setText("⏺ Enregistrer")
            self.rec_lbl.setText("")
            self._blink = False

        elif state == "recording":
            self.pair_combo.setEnabled(False)
            self.btn_record.setText("⏹ Stop")
            self.rec_lbl.setText("REC ●")
            self._blink = True

        elif state == "mvc":
            self.pair_combo.setEnabled(False)

    def _reset_axes(self, context: str):
        # helpers
        def style_plot(p: pg.PlotWidget, title: str, ylab: str, color_rgb):
            p.clear()
            p.setTitle(title, color=color_rgb)
            p.setLabel("bottom", "Temps (s)")
            p.setLabel("left", ylab)
            p.showGrid(x=True, y=True, alpha=0.2)
            if context in ("recording", "mvc"):
                p.setXRange(0, 5.0, padding=0)

        c1 = self.color_emg1
        c2 = self.color_emg2
        style_plot(self.p_raw1, "EMG1 brut", "Activité (V)", c1)
        style_plot(self.p_raw2, "EMG2 brut", "Activité (V)", c2)
        style_plot(self.p_filt1, "EMG1 filtré (normalisé)", "(%MVC)", c1)
        style_plot(self.p_filt2, "EMG2 filtré (normalisé)", "(%MVC)", c2)

        # live curves
        self.cur_raw1 = self.p_raw1.plot([], [], pen=pg.mkPen(c1, width=2))
        self.cur_raw2 = self.p_raw2.plot([], [], pen=pg.mkPen(c2, width=2))
        self.cur_filt1 = self.p_filt1.plot([], [], pen=pg.mkPen(c1, width=2))
        self.cur_filt2 = self.p_filt2.plot([], [], pen=pg.mkPen(c2, width=2))

    # ---------- channels ----------
    def _selected_pair(self) -> tuple[int, int]:
        idx = self.pair_combo.currentIndex()  # 0..6 corresponds to AI0-1 .. AI6-7
        ch1 = idx
        ch2 = idx + 1
        return ch1, ch2

    # ---------- connect/test ----------
    def _connect_daq(self):
        ch1, ch2 = self._selected_pair()

        if self.test_mode:
            self._set_status(f"Mode TEST (simulé) | paire AI{ch1}-{ch2}")
            return

        # hardware presence test (optional)
        if self.hw is None:
            self._set_status("Aucun backend hardware Python configuré. Activez 🧪 Test.", "red")
            return

        try:
            self.hw.test_read(ch1)
            self.hw.test_read(ch2)
            self._set_status(f"MCC détectée | paire AI{ch1}-{ch2}", "green")
        except Exception as e:
            self._set_status("Erreur hardware (test lecture). Activez 🧪 Test si besoin.", "red")
            print(e)

    def _toggle_test_mode(self):
        # stop recording if running
        if self.is_recording:
            self.btn_record.setChecked(False)
            self._start_stop_record()

        self.test_mode = self.btn_test.isChecked()

        if self.test_mode:
            self.sim_data = build_sim_data(self.Fs)
            self.sim_idx_record = 0
            self.sim_idx_mvc = 0
            self._set_status("Mode TEST activé (données simulées).")
        else:
            self.sim_data = None
            self.sim_idx_record = 0
            self.sim_idx_mvc = 0
            self._set_status("Mode TEST désactivé.")
        self._connect_daq()

    # ---------- acquisition unified ----------
    def _acquire_block_unified(self, kind: str, n_pts: int) -> np.ndarray:
        ch1, ch2 = self._selected_pair()

        if self.test_mode:
            if self.sim_data is None:
                self.sim_data = build_sim_data(self.Fs)
                self.sim_idx_record = 0
                self.sim_idx_mvc = 0

            if kind == "record":
                sig1, sig2 = self.sim_data.rec1, self.sim_data.rec2
                idx0 = self.sim_idx_record
            elif kind == "mvc":
                sig1, sig2 = self.sim_data.mvc1, self.sim_data.mvc2
                idx0 = self.sim_idx_mvc
            else:
                raise ValueError(f"Unknown kind={kind}")

            idx1 = idx0 + n_pts
            if idx1 > len(sig1):
                block = np.zeros((n_pts, 2), dtype=float)
            else:
                block = np.column_stack([sig1[idx0:idx1], sig2[idx0:idx1]])

            if kind == "record":
                self.sim_idx_record = idx1
            else:
                self.sim_idx_mvc = idx1

            return block

        # hardware path
        if self.hw is None:
            raise RuntimeError("Hardware backend not configured")
        v1, v2 = self.hw.read_block(ch1, ch2, n_pts, self.Fs)
        return np.column_stack([np.asarray(v1, float), np.asarray(v2, float)])

    # ---------- recording ----------
    def _start_stop_record(self):
        if self.btn_record.isChecked():
            # START
            self.raw_buf = np.empty((0, 2), dtype=float)
            self.is_recording = True

            if self.test_mode:
                self.sim_idx_record = 0

            self._reset_axes(context="recording")
            self._set_ui_state("recording")

            self._last_tick = time.perf_counter()
            self.timer.start(int(1000 * self.chunk_sec))

        else:
            # STOP
            self.is_recording = False
            self.timer.stop()
            self._set_ui_state("idle")

            if self.raw_buf.size == 0:
                return

            self._plot_final_and_store()

    def _on_timer_tick(self):
        # real-time pacing: QTimer is already pacing; keep extra safety for drift
        if not self.is_recording:
            return

        try:
            block = self._acquire_block_unified("record", self.chunk_pts)
        except Exception as e:
            self.is_recording = False
            self.timer.stop()
            self._set_ui_state("idle")
            self._set_status("Erreur pendant acquisition. Voir console.", "red")
            print(e)
            return

        self.raw_buf = np.vstack([self.raw_buf, block])

        # sliding window
        total_pts = self.raw_buf.shape[0]
        if total_pts <= self.window_pts:
            idx0 = 0
        else:
            idx0 = total_pts - self.window_pts

        win = self.raw_buf[idx0:total_pts]
        t = np.arange(win.shape[0]) / self.Fs

        ch1win = win[:, 0]
        ch2win = win[:, 1]

        # RAW live
        self.cur_raw1.setData(t, ch1win)
        self.cur_raw2.setData(t, ch2win)

        # FILTERED + NORMALISED live (like MATLAB)
        mvc1, mvc2 = self.mvc_values
        f1 = filter_emg(ch1win, self.Fs)
        f2 = filter_emg(ch2win, self.Fs)

        if mvc1 > 0:
            f1 = 100.0 * (f1 / mvc1)
        if mvc2 > 0:
            f2 = 100.0 * (f2 / mvc2)

        self.cur_filt1.setData(t, f1)
        self.cur_filt2.setData(t, f2)

        # blink REC
        if self._blink:
            self.rec_lbl.setText("" if self.rec_lbl.text() else "REC ●")

    def _plot_final_and_store(self):
        raw = self.raw_buf.copy()
        emg1 = raw[:, 0]
        emg2 = raw[:, 1]

        f1 = filter_emg(emg1, self.Fs)
        f2 = filter_emg(emg2, self.Fs)

        mvc1, mvc2 = self.mvc_values
        if mvc1 > 0:
            f1 = 100.0 * (f1 / mvc1)
        if mvc2 > 0:
            f2 = 100.0 * (f2 / mvc2)

        t_raw = np.arange(len(emg1)) / self.Fs
        t_flt = np.arange(len(f1)) / self.Fs

        # redraw full signals + overlay (approx transparency by lighter colour)
        self.p_raw1.clear()
        self.p_raw1.setTitle("EMG1 brut", color=self.color_emg1)
        self.p_raw1.setLabel("bottom", "Temps (s)")
        self.p_raw1.setLabel("left", "Activité (V)")
        self.p_raw1.plot(t_raw, emg1, pen=pg.mkPen(self.color_emg1, width=2))
        self.p_raw1.plot(t_raw, emg2, pen=pg.mkPen((*self._lighten(self.color_emg2, self.alpha_overlay),), width=2))

        self.p_raw2.clear()
        self.p_raw2.setTitle("EMG2 brut", color=self.color_emg2)
        self.p_raw2.setLabel("bottom", "Temps (s)")
        self.p_raw2.setLabel("left", "Activité (V)")
        self.p_raw2.plot(t_raw, emg2, pen=pg.mkPen(self.color_emg2, width=2))
        self.p_raw2.plot(t_raw, emg1, pen=pg.mkPen((*self._lighten(self.color_emg1, self.alpha_overlay),), width=2))

        self.p_filt1.clear()
        self.p_filt1.setTitle("EMG1 filtré (normalisé)", color=self.color_emg1)
        self.p_filt1.setLabel("bottom", "Temps (s)")
        self.p_filt1.setLabel("left", "(%MVC)")
        self.p_filt1.plot(t_flt, f1, pen=pg.mkPen(self.color_emg1, width=2))
        self.p_filt1.plot(t_flt, f2, pen=pg.mkPen((*self._lighten(self.color_emg2, self.alpha_overlay),), width=2))

        self.p_filt2.clear()
        self.p_filt2.setTitle("EMG2 filtré (normalisé)", color=self.color_emg2)
        self.p_filt2.setLabel("bottom", "Temps (s)")
        self.p_filt2.setLabel("left", "(%MVC)")
        self.p_filt2.plot(t_flt, f2, pen=pg.mkPen(self.color_emg2, width=2))
        self.p_filt2.plot(t_flt, f1, pen=pg.mkPen((*self._lighten(self.color_emg1, self.alpha_overlay),), width=2))

        # store
        self.rec_count += 1
        self.recordings_raw.append(raw)
        self._set_status(f"Enregistrement #{self.rec_count:02d} sauvegardé.")

    @staticmethod
    def _lighten(rgb, alpha):
        # alpha=0 -> original, alpha=1 -> white
        r, g, b = rgb
        r2 = int(r + (255 - r) * alpha)
        g2 = int(g + (255 - g) * alpha)
        b2 = int(b + (255 - b) * alpha)
        return r2, g2, b2

    # ---------- MVC ----------
    def _measure_mvc(self, which: int):
        if self.is_recording:
            return  # avoid conflict

        self._set_ui_state("mvc")
        self._reset_axes(context="mvc")
        self._set_status(f"Mesure MVC{which} en cours (5 s)...")

        if self.test_mode:
            self.sim_idx_mvc = 0

        dur_sec = 5.0
        n_pts = int(dur_sec * self.Fs)

        # stream MVC in real time (like MATLAB) using a local loop + processEvents
        buf = []
        idx = 0
        t0 = time.perf_counter()

        while idx < n_pts:
            loop_start = time.perf_counter()

            n_this = min(self.chunk_pts, n_pts - idx)
            block = self._acquire_block_unified("mvc", n_this)

            y = block[:, which - 1]
            buf.append(y)
            yall = np.concatenate(buf)

            t = np.arange(len(yall)) / self.Fs
            env = rms_envelope(yall, win=100)

            if which == 1:
                self.p_raw1.clear()
                self.p_raw1.setTitle(f"EMG1 MVC (5s)", color=self.color_emg1)
                self.p_raw1.setLabel("bottom", "Temps (s)")
                self.p_raw1.setLabel("left", "Activité (V)")
                self.p_raw1.plot(t, yall, pen=pg.mkPen(self.color_emg1, width=2))

                self.p_filt1.clear()
                self.p_filt1.setTitle("EMG1 enveloppe MVC", color=self.color_emg1)
                self.p_filt1.setLabel("bottom", "Temps (s)")
                self.p_filt1.setLabel("left", "(%MVC)")
                self.p_filt1.plot(t, env, pen=pg.mkPen(self.color_emg1, width=2))
            else:
                self.p_raw2.clear()
                self.p_raw2.setTitle(f"EMG2 MVC (5s)", color=self.color_emg2)
                self.p_raw2.setLabel("bottom", "Temps (s)")
                self.p_raw2.setLabel("left", "Activité (V)")
                self.p_raw2.plot(t, yall, pen=pg.mkPen(self.color_emg2, width=2))

                self.p_filt2.clear()
                self.p_filt2.setTitle("EMG2 enveloppe MVC", color=self.color_emg2)
                self.p_filt2.setLabel("bottom", "Temps (s)")
                self.p_filt2.setLabel("left", "(%MVC)")
                self.p_filt2.plot(t, env, pen=pg.mkPen(self.color_emg2, width=2))

            QtWidgets.QApplication.processEvents()

            # real-time pacing in test mode
            if self.test_mode:
                elapsed = time.perf_counter() - loop_start
                time.sleep(max(0.0, self.chunk_sec - elapsed))

            idx += n_this

        yall = np.concatenate(buf)
        if yall.size == 0 or not np.isfinite(yall).any():
            self._set_status(f"MVC{which} non mesuré (pas de signal).", "red")
            self._set_ui_state("idle")
            return

        n_take = min(2000, yall.size)
        mvc_val = np.median(np.partition(np.abs(yall), -n_take)[-n_take:])
        self.mvc_values[which - 1] = mvc_val
        self.mvc_lbl.setText(f"MVC1 = {self.mvc_values[0]:.2f} | MVC2 = {self.mvc_values[1]:.2f}")

        self._set_status(f"MVC{which} mesuré.")
        self._set_ui_state("idle")

    # ---------- exports ----------
    def _export_csv(self):
        if not self.recordings_raw:
            return
        raw = self.recordings_raw[-1]
        emg1 = raw[:, 0]
        emg2 = raw[:, 1]

        f1 = filter_emg(emg1, self.Fs)
        f2 = filter_emg(emg2, self.Fs)

        mvc1, mvc2 = self.mvc_values
        if mvc1 > 0:
            f1 = 100.0 * (f1 / mvc1)
        if mvc2 > 0:
            f2 = 100.0 * (f2 / mvc2)

        t = np.arange(raw.shape[0]) / self.Fs
        data = np.column_stack([t, emg1, emg2, f1, f2])

        path, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Exporter CSV sous...", filter="CSV (*.csv)")
        if not path:
            return

        header = "time_s,emg1_raw_V,emg2_raw_V,emg1_filt_pctMVC,emg2_filt_pctMVC"
        np.savetxt(path, data, delimiter=",", header=header, comments="", fmt="%.6f")

    def _export_png(self):
        # Simple: screenshot the widget (works cross-platform)
        path, _ = QtWidgets.QFileDialog.getSaveFileName(self, "Exporter les graphiques sous...", filter="PNG (*.png)")
        if not path:
            return
        pix = self.grab()
        pix.save(path, "PNG")

    # ---------- close ----------
    def closeEvent(self, event):
        self.is_recording = False
        self.timer.stop()
        event.accept()


def main():
    app = QtWidgets.QApplication(sys.argv)
    w = EMGGui()
    w.resize(1000, 750)
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
