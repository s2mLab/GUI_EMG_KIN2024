#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EMG GUI (Python) - MCC USB-1208FS-PLUS (mcculw + InstaCal) OR TEST MODE

Corrections demandées:
- Pendant l'acquisition ("Enregistrer"), chaque subplot n'affiche QUE son EMG (pas d'overlay).
- Les 2 courbes (overlay) ne s'affichent qu'APRES avoir stoppé l'acquisition (affichage final).
- Texte MVC déplacé vers la droite.
- Autoscale Y en temps réel (axes bruts + filtrés) avec lissage et fréquence limitée.
- Supprime les emojis (évite warnings de glyphes).
- Rend l'UI plus fluide: ring buffer + copies sans concat, autoscale limité, draw_idle.

Basé sur ton code fourni. :contentReference[oaicite:0]{index=0}
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from time import perf_counter
from typing import Tuple, Optional

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Button, RadioButtons, CheckButtons
from scipy.signal import butter, iirnotch, sosfilt, sosfilt_zi, sosfiltfilt, tf2sos, welch

# =========================
# CONFIG
# =========================
FS = 2000
WINDOW_SEC = 5
CHUNK_PTS = 200                 # ~0.1 s
UI_FPS = 25                     # UI refresh rate
MVC_DUR_SEC = 5

RMS_WIN_MS = 100
RMS_WIN = int(FS * RMS_WIN_MS / 1000)
LINE_FREQ_HZ = 60.0
SATURATION_V = 4.90
MIN_MVC_ENV_V = 0.01

# Autoscale
AUTOSCALE_HZ = 6
AUTOSCALE_SMOOTH = 0.25
AUTOSCALE_CHANGE_FRAC = 0.03
MIN_SPAN_RAW = 0.2              # V
MIN_SPAN_ENV = 5.0              # %MVC

COLOR_EMG1 = (0.0, 0.4470, 0.7410)
COLOR_EMG2 = (0.8500, 0.3250, 0.0980)
ALPHA_OVERLAY = 0.18

# MCC config
BOARD_NUM = 0
RANGE_NAME = "BIP5VOLTS"        # +/- 5 V


# =========================
# MCC BACKEND
# =========================
class MccBackend:
    """
    Minimal backend using mcculw.
    Note: block read here is done via repeated a_in calls paced to fs.
    If you later want higher performance, switch to UL scanning functions
    (a_in_scan) with circular buffer.
    """
    def __init__(self, board_num: int = BOARD_NUM, range_name: str = RANGE_NAME):
        self.board_num = board_num
        self.range_name = range_name
        self._ok = False
        self._err = None
        try:
            from mcculw import ul
            from mcculw.enums import ULRange
            self.ul = ul
            self.ULRange = ULRange
            self.ul_range = getattr(ULRange, range_name)
            self._ok = True
        except Exception as e:
            self._ok = False
            self._err = e

    @property
    def available(self) -> bool:
        return self._ok

    def read_one(self, ch: int) -> float:
        if not self._ok:
            raise RuntimeError(f"MCC backend unavailable: {self._err}")
        raw = self.ul.a_in(self.board_num, ch, self.ul_range)
        try:
            v = self.ul.to_eng_units(self.board_num, self.ul_range, raw)
            return float(v)
        except Exception:
            return float(raw)

    def read_block(self, ch1: int, ch2: int, n: int, fs: int) -> np.ndarray:
        block = np.empty((n, 2), dtype=float)
        t0 = perf_counter()
        for k in range(n):
            block[k, 0] = self.read_one(ch1)
            block[k, 1] = self.read_one(ch2)
            target = (k + 1) / fs
            dt = perf_counter() - t0
            if dt < target:
                time.sleep(target - dt)
        return block


# =========================
# SIM BACKEND
# =========================
@dataclass
class SimData:
    fs: int
    mvc1: np.ndarray
    mvc2: np.ndarray
    rec1: np.ndarray
    rec2: np.ndarray


def build_sim_data(fs: int = FS, seed: int = 1) -> SimData:
    rng = np.random.default_rng(seed)
    noise_std = 0.20
    f_line = 60.0
    line_amp = 0.30

    nmvc = MVC_DUR_SEC * fs
    t_mvc = np.arange(nmvc) / fs
    env = np.zeros(nmvc)
    env[:fs] = np.linspace(0, 1, fs)
    env[fs:4 * fs] = 1.0
    env[4 * fs:] = 0.0

    A1, A2 = 2.0, 3.0
    mvc1 = (A1 * env) * rng.standard_normal(nmvc) + noise_std * rng.standard_normal(nmvc)
    mvc2 = (A2 * env) * rng.standard_normal(nmvc) + noise_std * rng.standard_normal(nmvc) \
           + line_amp * np.sin(2 * np.pi * f_line * t_mvc)
    mvc1 -= mvc1.mean()
    mvc2 -= mvc2.mean()

    nrec = WINDOW_SEC * fs
    t_rec = np.arange(nrec) / fs
    rec1 = noise_std * rng.standard_normal(nrec)
    rec2 = noise_std * rng.standard_normal(nrec) + line_amp * np.sin(2 * np.pi * f_line * t_rec)

    # Muscle1 bursts
    burstA1 = 1.5
    nb1 = int(1.0 * fs)
    starts1 = [int(1.0 * fs), int(3.0 * fs)]
    car1 = rng.standard_normal(nrec)
    for s in starts1:
        idx = np.arange(s, min(s + nb1, nrec))
        rec1[idx] += burstA1 * car1[idx]

    # Muscle2 bursts
    burstA2 = 0.5
    nb2 = int(0.7 * fs)
    starts2 = [int(0.6 * fs), int(1.7 * fs), int(2.8 * fs), int(3.9 * fs)]
    car2 = rng.standard_normal(nrec)
    for s in starts2:
        idx = np.arange(s, min(s + nb2, nrec))
        rec2[idx] += burstA2 * car2[idx]

    rec1 -= rec1.mean()
    rec2 -= rec2.mean()

    return SimData(fs=fs, mvc1=mvc1, mvc2=mvc2, rec1=rec1, rec2=rec2)


class SimBackend:
    def __init__(self, sim: SimData):
        self.sim = sim
        self.idx_record = 0
        self.idx_mvc = 0

    def reset_record(self):
        self.idx_record = 0

    def reset_mvc(self):
        self.idx_mvc = 0

    def read_block(self, kind: str, n: int) -> np.ndarray:
        if kind == "record":
            sig1, sig2 = self.sim.rec1, self.sim.rec2
            idx0 = self.idx_record
        elif kind == "mvc":
            sig1, sig2 = self.sim.mvc1, self.sim.mvc2
            idx0 = self.idx_mvc
        else:
            raise ValueError("kind must be 'record' or 'mvc'")

        idx1 = idx0 + n
        if idx1 > len(sig1):
            block = np.zeros((n, 2))
        else:
            block = np.column_stack([sig1[idx0:idx1], sig2[idx0:idx1]])

        if kind == "record":
            self.idx_record = idx1
        else:
            self.idx_mvc = idx1
        return block


# =========================
# EMG CONDITIONING AND RMS ENVELOPE
# =========================
class EnvelopeRMS:
    """
    Streaming RMS envelope computed on a previously conditioned signal.
    """
    def __init__(self, win: int = RMS_WIN):
        self.win = max(1, int(win))
        self._sqbuf = np.zeros(self.win, dtype=float)
        self._sqsum = 0.0
        self._p = 0
        self._filled = 0

    def process(self, x: np.ndarray) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        y = np.empty_like(x)
        for i, xi in enumerate(x):
            sq = xi * xi

            self._sqsum -= self._sqbuf[self._p]
            self._sqbuf[self._p] = sq
            self._sqsum += sq

            self._p = (self._p + 1) % self.win
            self._filled = min(self.win, self._filled + 1)
            y[i] = np.sqrt(max(0.0, self._sqsum / self._filled))
        return y


def _emg_filter_sos(fs: int) -> np.ndarray:
    notch_b, notch_a = iirnotch(LINE_FREQ_HZ, 30.0, fs=fs)
    notch_sos = tf2sos(notch_b, notch_a)
    band_sos = butter(4, [20.0, 400.0], btype="bandpass", fs=fs, output="sos")
    return np.vstack([notch_sos, band_sos])


def process_emg_offline(raw: np.ndarray, fs: int) -> Tuple[np.ndarray, np.ndarray]:
    raw = np.asarray(raw, dtype=float)
    centered = raw - np.mean(raw) if raw.size else raw
    sos = _emg_filter_sos(fs)
    if centered.size > 3 * (2 * len(sos) + 1):
        filtered = sosfiltfilt(sos, centered)
    else:
        filtered = sosfilt(sos, centered)
    if filtered.size == 0:
        return filtered, filtered
    win = min(RMS_WIN, filtered.size)
    kernel = np.ones(win, dtype=float) / win
    envelope = np.sqrt(np.convolve(filtered * filtered, kernel, mode="same"))
    return filtered, envelope


class EMGStreamProcessor:
    """Streaming notch, band-pass and RMS processor for one EMG channel."""

    def __init__(self, fs: int):
        self.sos = _emg_filter_sos(fs)
        self.zi = sosfilt_zi(self.sos) * 0.0
        self.rms = EnvelopeRMS(RMS_WIN)

    def process(self, raw: np.ndarray) -> np.ndarray:
        filtered, self.zi = sosfilt(self.sos, np.asarray(raw, dtype=float), zi=self.zi)
        return self.rms.process(filtered)


def signal_quality_messages(raw: np.ndarray, fs: int, names: Optional[list[str]] = None) -> list[str]:
    raw = np.asarray(raw, dtype=float)
    if raw.ndim == 1:
        raw = raw[:, None]
    if raw.size == 0:
        return []

    messages = []
    sat_pct = 100.0 * np.mean(np.any(np.abs(raw) >= SATURATION_V, axis=1))
    if sat_pct > 0.5:
        messages.append(f"saturation {sat_pct:.1f}%")

    for channel in range(raw.shape[1]):
        name = names[channel] if names and channel < len(names) else f"EMG{channel + 1}"
        x = raw[:, channel]
        if np.std(x) < 0.005:
            messages.append(f"{name} tres faible")
            continue
        if x.size >= fs:
            freq, power = welch(x - np.mean(x), fs=fs, nperseg=min(x.size, fs))
            band_power = power[(freq >= 20) & (freq <= 400)].sum()
            line_power = power[(freq >= 59) & (freq <= 61)].sum()
            if band_power > 0 and line_power / band_power > 0.25:
                messages.append(f"{name} bruit 60 Hz eleve")
    return messages


# =========================
# GUI APP
# =========================
class EMGApp:
    def __init__(self):
        self.fs = FS
        self.window_sec = WINDOW_SEC
        self.buf_len = int(self.fs * self.window_sec)

        # State
        self.test_mode = True
        self.guided_mode = True
        self.is_recording = False
        self.mvc_values = np.array([0.0, 0.0], dtype=float)
        self.recordings_raw = []
        self.pair_idx = 0  # 0..6 => AI0-1..AI6-7

        # Backends
        self.mcc = MccBackend()
        self.sim = SimBackend(build_sim_data(self.fs))

        # Ring buffers (window only)
        self.raw1 = np.zeros(self.buf_len, dtype=float)
        self.raw2 = np.zeros(self.buf_len, dtype=float)
        self.env1 = np.zeros(self.buf_len, dtype=float)
        self.env2 = np.zeros(self.buf_len, dtype=float)
        self._write_pos = 0
        self._filled = 0

        # Prealloc plot arrays (no concat)
        self._plot_raw1 = np.zeros(self.buf_len, dtype=float)
        self._plot_raw2 = np.zeros(self.buf_len, dtype=float)
        self._plot_env1 = np.zeros(self.buf_len, dtype=float)
        self._plot_env2 = np.zeros(self.buf_len, dtype=float)

        self.envproc1 = EMGStreamProcessor(self.fs)
        self.envproc2 = EMGStreamProcessor(self.fs)

        # Full recording storage (only during record)
        self.full_record = []

        # Timing
        self.chunk_pts = CHUNK_PTS
        self.chunk_sec = self.chunk_pts / self.fs
        self.ui_period = 1.0 / UI_FPS
        self._next_acq_t: Optional[float] = None
        self._next_ui_t: Optional[float] = None

        # Autoscale
        self._autoscale_period = 1.0 / AUTOSCALE_HZ
        self._next_autoscale_t = 0.0
        self._ylim_cache = {}

        # UI
        self._build_ui()
        self._update_status()

        # Timer loop
        self._timer = self.fig.canvas.new_timer(interval=12)  # ~80 Hz tick, UI throttled to UI_FPS
        self._timer.add_callback(self._on_tick)
        self._timer.start()

    # ---------------- UI ----------------
    def _build_ui(self):
        self.fig = plt.figure(figsize=(14.0, 8.0))
        self.fig.canvas.manager.set_window_title("EMG Acquisition (MCC / TEST)")

        self.fig.subplots_adjust(left=0.06, right=0.98, top=0.72, bottom=0.12,
                                 wspace=0.18, hspace=0.35)

        self.guide_text = self.fig.text(0.06, 0.972, "", fontsize=12, ha="left",
                                        weight="bold", color=(0.08, 0.20, 0.45))
        self.mode_text = self.fig.text(0.06, 0.937, "", fontsize=11, ha="left")
        self.status_text = self.fig.text(0.06, 0.902, "Pret.", fontsize=11, ha="left")
        self.quality_text = self.fig.text(0.06, 0.730, "Qualite : en attente de signal",
                                          fontsize=11, ha="left", color=(0.25, 0.25, 0.25))
        self.mvc_text = self.fig.text(0.72, 0.937, "", fontsize=11, ha="left")
        self.rec_text = self.fig.text(0.48, 0.937, "", fontsize=12, ha="left",
                                      color="red", weight="bold")
        self._rec_blink = False

        self.ax_raw1 = self.fig.add_subplot(2, 2, 1)
        self.ax_raw2 = self.fig.add_subplot(2, 2, 2)
        self.ax_env1 = self.fig.add_subplot(2, 2, 3)
        self.ax_env2 = self.fig.add_subplot(2, 2, 4)

        self._style_axes()

        # Live lines: ONLY single-channel during acquisition
        (self.line_raw1,) = self.ax_raw1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_raw2,) = self.ax_raw2.plot([], [], color=COLOR_EMG2, lw=1.0)
        (self.line_env1,) = self.ax_env1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_env2,) = self.ax_env2.plot([], [], color=COLOR_EMG2, lw=1.0)

        # Overlay lines exist but will be shown ONLY in final plots after stop
        (self.line_raw1_ol,) = self.ax_raw1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_raw2_ol,) = self.ax_raw2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env1_ol,) = self.ax_env1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env2_ol,) = self.ax_env2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        self._set_overlay_visible(False)

        # Controls
        ax_pair = self.fig.add_axes([0.06, 0.745, 0.14, 0.13])
        ax_test = self.fig.add_axes([0.22, 0.77, 0.12, 0.095])
        ax_mvc1 = self.fig.add_axes([0.38, 0.785, 0.10, 0.06])
        ax_mvc2 = self.fig.add_axes([0.49, 0.785, 0.10, 0.06])
        ax_rec = self.fig.add_axes([0.61, 0.785, 0.14, 0.06])

        ax_exp_png = self.fig.add_axes([0.74, 0.02, 0.11, 0.07])
        ax_exp_csv = self.fig.add_axes([0.86, 0.02, 0.11, 0.07])

        pair_labels = [f"AI{k}-{k+1}" for k in range(7)]
        self.rb_pair = RadioButtons(ax_pair, pair_labels, active=self.pair_idx)
        self.rb_pair.on_clicked(self._on_pair_changed)

        self.cb_test = CheckButtons(ax_test, ["TEST", "GUIDE"], [self.test_mode, self.guided_mode])
        self.cb_test.on_clicked(self._on_toggle_mode_checkbox)
        ax_test.set_title("Mode", fontsize=10, pad=2)

        self.btn_rec = Button(ax_rec, "Enregistrer")
        self.btn_rec.on_clicked(self._on_toggle_record)

        self.btn_mvc1 = Button(ax_mvc1, "MVC 1")
        self.btn_mvc2 = Button(ax_mvc2, "MVC 2")
        self.btn_mvc1.on_clicked(lambda _evt: self._run_mvc(1))
        self.btn_mvc2.on_clicked(lambda _evt: self._run_mvc(2))

        self.btn_png = Button(ax_exp_png, "Exporter PNG")
        self.btn_csv = Button(ax_exp_csv, "Exporter CSV")
        self.btn_png.on_clicked(self._export_png)
        self.btn_csv.on_clicked(self._export_csv)

        self.fig.canvas.mpl_connect("close_event", self._on_close)

    def _style_axes(self):
        for ax in (self.ax_raw1, self.ax_raw2, self.ax_env1, self.ax_env2):
            ax.set_xlim(-self.window_sec, 0.0)
            ax.grid(True, alpha=0.25)
            ax.set_xlabel("Temps (s)")

        self.ax_raw1.set_title("EMG1 brut", color=COLOR_EMG1)
        self.ax_raw2.set_title("EMG2 brut", color=COLOR_EMG2)
        self.ax_raw1.set_ylabel("Activité (V)")
        self.ax_raw2.set_ylabel("Activité (V)")
        self._update_envelope_labels()

        self.ax_raw1.set_ylim(-0.2, 0.2)
        self.ax_raw2.set_ylim(-0.2, 0.2)
        self.ax_env1.set_ylim(0, 30)
        self.ax_env2.set_ylim(0, 30)

    def _set_overlay_visible(self, visible: bool):
        for ln in (self.line_raw1_ol, self.line_raw2_ol, self.line_env1_ol, self.line_env2_ol):
            ln.set_visible(visible)

    # -------------- status / callbacks --------------
    def _selected_channels(self) -> Tuple[int, int]:
        return self.pair_idx, self.pair_idx + 1

    def _has_mvc(self, which: int) -> bool:
        return bool(self.mvc_values[which - 1] > 0)

    def _update_envelope_labels(self):
        for which, ax, col in ((1, self.ax_env1, COLOR_EMG1), (2, self.ax_env2, COLOR_EMG2)):
            if self._has_mvc(which):
                ax.set_title(f"EMG{which} enveloppe normalisee", color=col)
                ax.set_ylabel("Activation (%MVC)")
            else:
                ax.set_title(f"EMG{which} enveloppe RMS", color=col)
                ax.set_ylabel("Enveloppe RMS (V)")

    def _update_guidance(self):
        if not self.guided_mode:
            instruction = "Mode libre : calibrez les MVC avant d'interpreter une valeur en %MVC."
        elif not self._has_mvc(1):
            instruction = "Etape 1/4 - Mesurez MVC 1 pendant une contraction maximale de 5 s."
        elif not self._has_mvc(2):
            instruction = "Etape 2/4 - Mesurez MVC 2 pendant une contraction maximale de 5 s."
        elif not self.recordings_raw:
            instruction = "Etape 3/4 - Les deux MVC sont pretes : lancez Enregistrer."
        else:
            instruction = "Etape 4/4 - Interpretez les courbes puis exportez PNG ou CSV."
        self.guide_text.set_text(instruction)

    def _set_quality(self, raw: np.ndarray, names: Optional[list[str]] = None):
        messages = signal_quality_messages(raw, self.fs, names)
        if messages:
            self.quality_text.set_color((0.75, 0.10, 0.05))
            self.quality_text.set_text("Qualite : attention - " + "; ".join(messages))
        else:
            self.quality_text.set_color((0.0, 0.45, 0.20))
            self.quality_text.set_text("Qualite : signal exploitable")

    def _update_status(self):
        ch1, ch2 = self._selected_channels()
        if self.test_mode:
            self.mode_text.set_text(f"Mode TEST (simule) | paire AI{ch1}-{ch2}")
        else:
            if self.mcc.available:
                self.mode_text.set_text(f"Mode HARDWARE (MCC) | paire AI{ch1}-{ch2}")
            else:
                self.mode_text.set_text("MCC indisponible - cochez TEST (mcculw + InstaCal requis)")
        self.mvc_text.set_text(f"MVC1 = {self.mvc_values[0]:.3f} | MVC2 = {self.mvc_values[1]:.3f}")
        self._update_envelope_labels()
        self._update_guidance()

    def _on_pair_changed(self, label: str):
        if self.is_recording:
            return
        k = int(label.split("AI")[1].split("-")[0])
        self.pair_idx = k
        self._update_status()
        self.fig.canvas.draw_idle()

    def _on_toggle_mode_checkbox(self, label: str):
        # ignore toggle while recording: revert checkbox to actual state (no desync)
        if self.is_recording:
            idx = 0 if label == "TEST" else 1
            desired = self.test_mode if idx == 0 else self.guided_mode
            current = bool(self.cb_test.get_status()[idx])
            if current != desired:
                self.cb_test.set_active(idx)  # flip back
            return

        if label == "TEST":
            self.test_mode = bool(self.cb_test.get_status()[0])
            if self.test_mode:
                self.sim.reset_record()
                self.sim.reset_mvc()
        else:
            self.guided_mode = bool(self.cb_test.get_status()[1])
        self._update_status()
        self.fig.canvas.draw_idle()

    def _on_toggle_record(self, _evt):
        if self.is_recording:
            self._stop_recording()
        else:
            self._start_recording()

    def _on_close(self, _evt):
        self.is_recording = False

    # -------------- acquisition / ring buffer --------------
    def _acquire_block(self, kind: str, n: int) -> np.ndarray:
        ch1, ch2 = self._selected_channels()
        if self.test_mode:
            return self.sim.read_block(kind=kind, n=n)
        return self.mcc.read_block(ch1=ch1, ch2=ch2, n=n, fs=self.fs)

    def _push_block(self, block: np.ndarray):
        x1 = block[:, 0]
        x2 = block[:, 1]
        y1 = self.envproc1.process(x1)
        y2 = self.envproc2.process(x2)

        n = len(x1)
        pos = self._write_pos
        end = pos + n

        if end <= self.buf_len:
            self.raw1[pos:end] = x1
            self.raw2[pos:end] = x2
            self.env1[pos:end] = y1
            self.env2[pos:end] = y2
        else:
            k = self.buf_len - pos
            self.raw1[pos:] = x1[:k]
            self.raw2[pos:] = x2[:k]
            self.env1[pos:] = y1[:k]
            self.env2[pos:] = y2[:k]
            r = n - k
            self.raw1[:r] = x1[k:]
            self.raw2[:r] = x2[k:]
            self.env1[:r] = y1[k:]
            self.env2[:r] = y2[k:]

        self._write_pos = (pos + n) % self.buf_len
        self._filled = min(self.buf_len, self._filled + n)

    def _fill_plot_array(self, src: np.ndarray, dst: np.ndarray) -> int:
        n = self._filled
        if n == 0:
            return 0
        if n < self.buf_len:
            dst[:n] = src[:n]
            return n

        p = self._write_pos
        n1 = self.buf_len - p
        dst[:n1] = src[p:]
        dst[n1:self.buf_len] = src[:p]
        return self.buf_len

    # -------------- recording --------------
    def _start_recording(self):
        if self.guided_mode and not all(self.mvc_values > 0):
            self.status_text.set_text("Mesurez MVC 1 et MVC 2 avant d'enregistrer en mode GUIDE.")
            self.fig.canvas.draw_idle()
            return
        if (not self.test_mode) and (not self.mcc.available):
            self.status_text.set_text("MCC non disponible. Coche TEST.")
            self.fig.canvas.draw_idle()
            return

        # reset buffers
        self.raw1[:] = 0
        self.raw2[:] = 0
        self.env1[:] = 0
        self.env2[:] = 0
        self._write_pos = 0
        self._filled = 0
        self.envproc1 = EMGStreamProcessor(self.fs)
        self.envproc2 = EMGStreamProcessor(self.fs)
        self.full_record = []

        self.is_recording = True
        self.btn_rec.label.set_text("Stop")
        self.rec_text.set_text("REC")
        self.status_text.set_text("Enregistrement en cours...")
        self._rec_blink = False

        # during recording: overlays hidden
        self._set_overlay_visible(False)

        if self.test_mode:
            self.sim.reset_record()

        # reset axis view to live mode without clearing widgets
        self._reset_live_view()

        now = perf_counter()
        self._next_acq_t = now
        self._next_ui_t = now
        self._next_autoscale_t = now

    def _stop_recording(self):
        self.is_recording = False
        self.btn_rec.label.set_text("Enregistrer")
        self.rec_text.set_text("")
        self._rec_blink = False

        if len(self.full_record) == 0:
            return

        rawBuf = np.vstack(self.full_record)
        self.recordings_raw.append(rawBuf)
        self._set_quality(rawBuf)

        # after stop: show final with overlays
        self._plot_final(rawBuf)
        self.status_text.set_text(f"Enregistrement sauvegardé ({rawBuf.shape[0]/self.fs:.2f}s).")
        self.fig.canvas.draw_idle()

    # -------------- main tick --------------
    def _on_tick(self):
        if not self.is_recording:
            self._update_status()
            return

        now = perf_counter()

        # acquisition catch-up (bounded)
        max_catchup_blocks = 3
        n_catch = 0
        while now >= self._next_acq_t and n_catch < max_catchup_blocks and self.is_recording:
            block = self._acquire_block(kind="record", n=self.chunk_pts)
            self.full_record.append(block)
            self._push_block(block)
            self._next_acq_t += self.chunk_sec
            n_catch += 1
            now = perf_counter()

        # if huge lag, resync (prevents endless drift)
        if now - self._next_acq_t > 0.5:
            self._next_acq_t = now

        # UI update
        if now >= self._next_ui_t:
            self._update_live_lines(now)
            self._blink_rec()
            self.fig.canvas.draw_idle()
            self._next_ui_t += self.ui_period
            if now - self._next_ui_t > 0.5:
                self._next_ui_t = now

    def _blink_rec(self):
        self._rec_blink = not self._rec_blink
        self.rec_text.set_text("" if self._rec_blink else "REC")

    # -------------- live plot update --------------
    def _update_live_lines(self, now: float):
        if self._filled == 0:
            return

        n = self._fill_plot_array(self.raw1, self._plot_raw1)
        self._fill_plot_array(self.raw2, self._plot_raw2)
        self._fill_plot_array(self.env1, self._plot_env1)
        self._fill_plot_array(self.env2, self._plot_env2)

        raw1 = self._plot_raw1[:n]
        raw2 = self._plot_raw2[:n]
        env1 = self._plot_env1[:n]
        env2 = self._plot_env2[:n]

        mvc1, mvc2 = self.mvc_values
        env1n = (100.0 * env1 / mvc1) if mvc1 > 0 else env1
        env2n = (100.0 * env2 / mvc2) if mvc2 > 0 else env2

        t = np.linspace(-self.window_sec, 0.0, n, endpoint=True)

        # During recording: ONLY the channel itself (no overlay)
        self.line_raw1.set_data(t, raw1)
        self.line_raw2.set_data(t, raw2)
        self.line_env1.set_data(t, env1n)
        self.line_env2.set_data(t, env2n)

        # Autoscale throttled
        if now >= self._next_autoscale_t:
            self._autoscale_axis(self.ax_raw1, raw1, key="raw1", min_span=MIN_SPAN_RAW)
            self._autoscale_axis(self.ax_raw2, raw2, key="raw2", min_span=MIN_SPAN_RAW)
            self._autoscale_axis(self.ax_env1, env1n, key="env1", min_span=MIN_SPAN_ENV, floor=0.0)
            self._autoscale_axis(self.ax_env2, env2n, key="env2", min_span=MIN_SPAN_ENV, floor=0.0)
            self._next_autoscale_t = now + self._autoscale_period

        self._update_status()

    def _autoscale_axis(self, ax, y, key: str, min_span: float, floor: Optional[float] = None):
        y = np.asarray(y)
        if y.size == 0:
            return
        ymin = float(np.nanmin(y))
        ymax = float(np.nanmax(y))
        if not np.isfinite(ymin) or not np.isfinite(ymax):
            return

        if ymax - ymin < min_span:
            mid = 0.5 * (ymax + ymin)
            ymin = mid - 0.5 * min_span
            ymax = mid + 0.5 * min_span

        if floor is not None:
            ymin = max(floor, ymin)

        pad = 0.08 * (ymax - ymin)
        target = (ymin - pad, ymax + pad)

        cur = self._ylim_cache.get(key)
        if cur is None:
            ax.set_ylim(*target)
            self._ylim_cache[key] = target
            return

        cur_span = max(1e-12, cur[1] - cur[0])
        tgt_span = max(1e-12, target[1] - target[0])

        if abs(tgt_span - cur_span) / cur_span < AUTOSCALE_CHANGE_FRAC and \
           abs(target[0] - cur[0]) / cur_span < AUTOSCALE_CHANGE_FRAC and \
           abs(target[1] - cur[1]) / cur_span < AUTOSCALE_CHANGE_FRAC:
            return

        a = AUTOSCALE_SMOOTH
        new0 = (1 - a) * cur[0] + a * target[0]
        new1 = (1 - a) * cur[1] + a * target[1]
        ax.set_ylim(new0, new1)
        self._ylim_cache[key] = (new0, new1)

    # -------------- MVC --------------
    def _run_mvc(self, which: int):
        if self.is_recording:
            return
        if (not self.test_mode) and (not self.mcc.available):
            self.status_text.set_text("MCC non disponible. Coche TEST.")
            self.fig.canvas.draw_idle()
            return

        if self.test_mode:
            self.sim.reset_mvc()

        self.status_text.set_text(f"Mesure MVC{which} en cours (5 s)...")
        self.fig.canvas.draw_idle()

        n_total = int(MVC_DUR_SEC * self.fs)

        if which == 1:
            ax_raw, ax_env, col = self.ax_raw1, self.ax_env1, COLOR_EMG1
        else:
            ax_raw, ax_env, col = self.ax_raw2, self.ax_env2, COLOR_EMG2

        # --- axes reset ---
        ax_raw.cla()
        ax_env.cla()
        ax_raw.grid(True, alpha=0.25)
        ax_env.grid(True, alpha=0.25)
        ax_raw.set_xlabel("Temps (s)")
        ax_env.set_xlabel("Temps (s)")
        ax_raw.set_ylabel("Activité (V)")
        ax_env.set_ylabel("Enveloppe RMS (V)")
        ax_raw.set_title(f"EMG{which} MVC (5s)", color=col)
        ax_env.set_title(f"EMG{which} enveloppe MVC", color=col)
        ax_raw.set_xlim(0, MVC_DUR_SEC)
        ax_env.set_xlim(0, MVC_DUR_SEC)

        # ==========================
        # PREALLOCATION (KEY CHANGE)
        # ==========================
        t = np.arange(n_total) / self.fs

        # Use NaNs for "not yet acquired" points (matplotlib won't draw them)
        y_raw = np.full(n_total, np.nan, dtype=float)
        y_env = np.full(n_total, np.nan, dtype=float)

        # Create lines once, set x once, then only update y arrays
        (line_raw,) = ax_raw.plot(t, y_raw, color=col, lw=1.0)
        (line_env,) = ax_env.plot(t, y_env, color=col, lw=1.0)

        envproc = EMGStreamProcessor(self.fs)

        idx = 0
        next_t = perf_counter()

        while idx < n_total and plt.fignum_exists(self.fig.number):
            n_this = min(self.chunk_pts, n_total - idx)
            block = self._acquire_block(kind="mvc", n=n_this)
            x = block[:, which - 1]

            # Fill the preallocated arrays
            y_raw[idx:idx + n_this] = x

            # Process each new block exactly once through the streaming filter.
            y_env[idx:idx + n_this] = envproc.process(x)

            idx += n_this

            # Update ONLY ydata (x is fixed)
            line_raw.set_ydata(y_raw)
            line_env.set_ydata(y_env)

            # autoscale based only on acquired samples
            acquired_raw = y_raw[:idx]
            acquired_env = y_env[:idx]
            self._autoscale_axis(ax_raw, acquired_raw[np.isfinite(acquired_raw)],
                                 key=f"mvc_raw_{which}", min_span=MIN_SPAN_RAW)
            self._autoscale_axis(ax_env, acquired_env[np.isfinite(acquired_env)],
                                 key=f"mvc_env_{which}", min_span=MIN_SPAN_ENV, floor=0.0)

            self.fig.canvas.draw_idle()
            plt.pause(0.001)

            # real-time pacing
            next_t += n_this / self.fs
            delay = next_t - perf_counter()
            if delay > 0:
                time.sleep(delay)

        # Final buffer (only acquired)
        x_final = y_raw[:idx]
        x_final = x_final[np.isfinite(x_final)]
        if x_final.size == 0:
            self.status_text.set_text(f"MVC{which} non mesuré (pas de signal).")
            self.fig.canvas.draw_idle()
            return

        acquired_env = y_env[:idx]
        acquired_env = acquired_env[np.isfinite(acquired_env)]
        n_take = min(2000, acquired_env.size)
        top_vals = np.partition(acquired_env, -n_take)[-n_take:]
        mvc_val = float(np.median(top_vals))
        self._set_quality(x_final, [f"EMG{which}"])
        if mvc_val < MIN_MVC_ENV_V:
            self.status_text.set_text(f"MVC{which} insuffisante : recommencez la mesure.")
            self.fig.canvas.draw_idle()
            return
        self.mvc_values[which - 1] = mvc_val

        self.status_text.set_text(f"MVC{which} mesuree. Calibration disponible pour EMG{which}.")
        self._update_status()
        self.fig.canvas.draw_idle()

    # -------------- final plots + export --------------
    def _plot_final(self, rawBuf: np.ndarray):
        """
        Final view after STOP: show overlays (both curves) on raw and filtered.
        """
        emg1 = rawBuf[:, 0]
        emg2 = rawBuf[:, 1]
        t = np.arange(rawBuf.shape[0]) / self.fs

        _, env1 = process_emg_offline(emg1, self.fs)
        _, env2 = process_emg_offline(emg2, self.fs)

        mvc1, mvc2 = self.mvc_values
        env1n = 100.0 * env1 / mvc1 if mvc1 > 0 else env1
        env2n = 100.0 * env2 / mvc2 if mvc2 > 0 else env2

        # Clear axes and draw final with overlays
        for ax in (self.ax_raw1, self.ax_raw2, self.ax_env1, self.ax_env2):
            ax.cla()

        self.ax_raw1.plot(t, emg1, color=COLOR_EMG1, lw=1.0)
        self.ax_raw1.plot(t, emg2, color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_raw1.set_title("EMG1 brut", color=COLOR_EMG1)
        self.ax_raw1.set_xlabel("Temps (s)"); self.ax_raw1.set_ylabel("Activité (V)")
        self.ax_raw1.grid(True, alpha=0.25)

        self.ax_raw2.plot(t, emg2, color=COLOR_EMG2, lw=1.0)
        self.ax_raw2.plot(t, emg1, color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_raw2.set_title("EMG2 brut", color=COLOR_EMG2)
        self.ax_raw2.set_xlabel("Temps (s)"); self.ax_raw2.set_ylabel("Activité (V)")
        self.ax_raw2.grid(True, alpha=0.25)

        self.ax_env1.plot(t, env1n, color=COLOR_EMG1, lw=1.0)
        self.ax_env1.plot(t, env2n, color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_env1.set_xlabel("Temps (s)")
        self.ax_env1.grid(True, alpha=0.25)

        self.ax_env2.plot(t, env2n, color=COLOR_EMG2, lw=1.0)
        self.ax_env2.plot(t, env1n, color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_env2.set_xlabel("Temps (s)")
        self.ax_env2.grid(True, alpha=0.25)
        self._update_envelope_labels()

        self.fig.canvas.draw_idle()

    def _export_png(self, _evt):
        fname = time.strftime("emg_graphs_%Y%m%d_%H%M%S.png")
        self.fig.savefig(fname, dpi=160)
        self.status_text.set_text(f"PNG exporté: {fname}")
        self.fig.canvas.draw_idle()

    def _export_csv(self, _evt):
        if not self.recordings_raw:
            self.status_text.set_text("Aucun enregistrement à exporter.")
            self.fig.canvas.draw_idle()
            return

        rawBuf = self.recordings_raw[-1]
        t = np.arange(rawBuf.shape[0]) / self.fs
        emg1 = rawBuf[:, 0]
        emg2 = rawBuf[:, 1]

        _, env1 = process_emg_offline(emg1, self.fs)
        _, env2 = process_emg_offline(emg2, self.fs)

        mvc1, mvc2 = self.mvc_values
        env1n = 100.0 * env1 / mvc1 if mvc1 > 0 else env1
        env2n = 100.0 * env2 / mvc2 if mvc2 > 0 else env2

        out = np.column_stack([t, emg1, emg2, env1n, env2n])
        fname = time.strftime("emg_last_%Y%m%d_%H%M%S.csv")
        env1_unit = "pctMVC" if mvc1 > 0 else "V"
        env2_unit = "pctMVC" if mvc2 > 0 else "V"
        header = f"time_s,emg1_raw_V,emg2_raw_V,emg1_env_{env1_unit},emg2_env_{env2_unit}"
        np.savetxt(fname, out, delimiter=",", header=header, comments="")
        self.status_text.set_text(f"CSV exporté: {fname}")
        self.fig.canvas.draw_idle()

    def _reset_live_view(self):
        """
        Reset axes to live view (single-channel lines only),
        keep the GUI widgets (they are separate axes).
        """
        for ax in (self.ax_raw1, self.ax_raw2, self.ax_env1, self.ax_env2):
            ax.cla()

        self._style_axes()

        (self.line_raw1,) = self.ax_raw1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_raw2,) = self.ax_raw2.plot([], [], color=COLOR_EMG2, lw=1.0)
        (self.line_env1,) = self.ax_env1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_env2,) = self.ax_env2.plot([], [], color=COLOR_EMG2, lw=1.0)

        (self.line_raw1_ol,) = self.ax_raw1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_raw2_ol,) = self.ax_raw2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env1_ol,) = self.ax_env1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env2_ol,) = self.ax_env2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        self._set_overlay_visible(False)

    

def main():
    _ = EMGApp()
    plt.show()


if __name__ == "__main__":
    main()
