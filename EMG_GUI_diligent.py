#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EMG GUI (Python) — MCC/Digilent USB-1206FS-PLUS (Universal Library / InstaCal) OR TEST MODE

Key features (mirrors your MATLAB GUI logic):
- Pair selector: AI0-1, AI1-2, ... AI6-7
- Start/Stop recording: live RAW (top) + live filtered/envelope normalised (%MVC) (bottom)
- MVC1 / MVC2 acquisition (5 s) streaming in real time
- Blinking “REC ●” while recording
- Export PNG of graphs + Export CSV of last recording
- TEST mode with deterministic simulated EMG (mean ~ 0, amplitude-modulated bursts; 60 Hz line on channel 2)

IMPORTANT ABOUT PERFORMANCE / LAG:
- Uses a FIXED-SIZE RING BUFFER (last 5 s) for live display (constant cost).
- Uses a REAL-TIME CLOCK with drift correction (no accumulating lag).
- Throttles UI updates to ~20 Hz (configurable).
- Live "filtered" is a lightweight RMS envelope (streaming-friendly).
  (You can swap to causal IIR filtering later; avoid filtfilt for live.)

Dependencies:
- Python 3.10+ recommended
- numpy, scipy, matplotlib
- For MCC hardware (optional): mcculw (Measurement Computing Universal Library for Python)
  pip install mcculw

Hardware notes:
- Uses single-sample AIn reads in a loop for simplicity. For better performance,
  you can later replace with scan (AInScan) via mcculw.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from time import perf_counter
from typing import Optional, Tuple

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Button, RadioButtons
from scipy.signal import butter, sosfilt, sosfilt_zi, iirnotch, lfilter

# =========================
# CONFIG
# =========================
FS = 2000                      # Hz
WINDOW_SEC = 5                 # seconds shown in live plots
CHUNK_PTS = 200                # samples per acquisition step (~0.1 s)
UI_FPS = 20                    # UI refresh rate (Hz) -> ~20 Hz smooth enough
MVC_DUR_SEC = 5
RMS_WIN_MS = 100               # for envelope
RMS_WIN = int(FS * RMS_WIN_MS / 1000)

COLOR_EMG1 = (0.0, 0.4470, 0.7410)
COLOR_EMG2 = (0.8500, 0.3250, 0.0980)
ALPHA_OVERLAY = 0.20

# MCC config (change if needed)
BOARD_NUM = 0
RANGE_NAME = "BIP5VOLTS"       # +/- 5V range (USB-1206FS-PLUS supports)

# =========================
# MCC HARDWARE BACKEND (optional)
# =========================
class MccBackend:
    """
    Minimal MCC UL backend via mcculw.
    If mcculw is not installed or device not available, you can still run in TEST mode.
    """
    def __init__(self, board_num: int = BOARD_NUM, range_name: str = RANGE_NAME):
        self.board_num = board_num
        self.range_name = range_name
        self._ok = False

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

    def test_read(self, ch: int) -> float:
        """Single sample read (volts)."""
        if not self._ok:
            raise RuntimeError(f"MCC backend unavailable: {getattr(self,'_err',None)}")
        # a_in returns engineering units depending on config; for safety we use a_in + to_eng_units
        # Some UL configurations can return raw counts. We'll handle both.
        raw = self.ul.a_in(self.board_num, ch, self.ul_range)
        try:
            volts = self.ul.to_eng_units(self.board_num, self.ul_range, raw)
            return float(volts)
        except Exception:
            # if ul.a_in already returns volts
            return float(raw)

    def read_block(self, ch1: int, ch2: int, n: int, fs: int) -> np.ndarray:
        """Read block as Nx2 volts using repeated single-sample reads (simple, robust)."""
        block = np.empty((n, 2), dtype=float)
        # Pace precisely to fs
        t0 = perf_counter()
        for k in range(n):
            v1 = self.test_read(ch1)
            v2 = self.test_read(ch2)
            block[k, 0] = v1
            block[k, 1] = v2
            target = (k + 1) / fs
            dt = perf_counter() - t0
            if dt < target:
                time.sleep(target - dt)
        return block


# =========================
# SIMULATION BACKEND
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

    noise_std = 0.2
    f_line = 60.0
    line_amp = 0.3

    # MVC 5s: ramp 1s, hold 3s, rest 1s (amplitude changes; mean ~ 0)
    nmvc = MVC_DUR_SEC * fs
    t_mvc = np.arange(nmvc) / fs
    env = np.zeros(nmvc)
    env[:fs] = np.linspace(0, 1, fs)              # ramp
    env[fs:4 * fs] = 1.0                          # hold 3s
    env[4 * fs:] = 0.0                            # rest 1s

    A1, A2 = 2.0, 3.0
    mvc1 = (A1 * env) * rng.standard_normal(nmvc) + noise_std * rng.standard_normal(nmvc)
    mvc2 = (A2 * env) * rng.standard_normal(nmvc) + noise_std * rng.standard_normal(nmvc) \
           + line_amp * np.sin(2 * np.pi * f_line * t_mvc)

    mvc1 -= mvc1.mean()
    mvc2 -= mvc2.mean()

    # Recording 5s
    nrec = WINDOW_SEC * fs
    t_rec = np.arange(nrec) / fs

    rec1 = noise_std * rng.standard_normal(nrec)
    rec2 = noise_std * rng.standard_normal(nrec) + line_amp * np.sin(2 * np.pi * f_line * t_rec)

    # Muscle 1 bursts: two bursts 1.5V, 1s each at 1s and 3s
    burstA1 = 1.5
    nb1 = int(1.0 * fs)
    starts1 = [int(1.0 * fs), int(3.0 * fs)]
    car1 = rng.standard_normal(nrec)
    for s in starts1:
        idx = np.arange(s, min(s + nb1, nrec))
        rec1[idx] += burstA1 * car1[idx]

    # Muscle 2 bursts: four bursts 0.5V, 0.7s each
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
    """Streaming simulator with separate indices for recording and MVC (like your MATLAB script)."""
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
# STREAMING ENVELOPE FILTER (fast)
# =========================
class EnvelopeRMS:
    """
    Streaming RMS envelope: y = sqrt(movmean((x - mean)^2, win))
    For streaming: we do a simple high-pass by subtracting running mean (EWMA),
    then compute RMS with a running window using cumulative sum of squares.

    This is lightweight and avoids filtfilt (good for live).
    """
    def __init__(self, win: int = RMS_WIN, alpha_mean: float = 0.01):
        self.win = max(1, int(win))
        self.alpha_mean = float(alpha_mean)
        self._mean = 0.0
        self._sqbuf = np.zeros(self.win, dtype=float)
        self._sqsum = 0.0
        self._p = 0
        self._filled = 0

    def process(self, x: np.ndarray) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        y = np.empty_like(x)
        for i, xi in enumerate(x):
            # EWMA mean removal (keeps mean ~0)
            self._mean = (1 - self.alpha_mean) * self._mean + self.alpha_mean * xi
            xc = xi - self._mean
            sq = xc * xc

            # ring buffer of squares
            self._sqsum -= self._sqbuf[self._p]
            self._sqbuf[self._p] = sq
            self._sqsum += sq

            self._p = (self._p + 1) % self.win
            self._filled = min(self.win, self._filled + 1)
            y[i] = np.sqrt(self._sqsum / self._filled)
        return y


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
        self.is_recording = False
        self.mvc_values = np.array([0.0, 0.0], dtype=float)
        self.recordings_raw = []  # list of Nx2 arrays (full recordings)

        # Channel pair selection (AI0-1 default)
        self.pair_idx = 0  # 0..6 => AI0-1..AI6-7

        # Backends
        self.mcc = MccBackend()
        self.sim = SimBackend(build_sim_data(self.fs))

        # Live ring buffers (raw + envelope)
        self.raw1 = np.zeros(self.buf_len, dtype=float)
        self.raw2 = np.zeros(self.buf_len, dtype=float)
        self.env1 = np.zeros(self.buf_len, dtype=float)
        self.env2 = np.zeros(self.buf_len, dtype=float)
        self._write_pos = 0
        self._filled = 0

        # Streaming envelope processors (per channel)
        self.envproc1 = EnvelopeRMS(RMS_WIN)
        self.envproc2 = EnvelopeRMS(RMS_WIN)

        # UI timing / drift control
        self.chunk_pts = CHUNK_PTS
        self.chunk_sec = self.chunk_pts / self.fs
        self.ui_period = 1.0 / UI_FPS
        self._next_acq_t = None
        self._next_ui_t = None

        # Build GUI
        self._build_ui()
        self._update_status()

        # Timer-driven loop via matplotlib's event loop
        self._timer = self.fig.canvas.new_timer(interval=5)  # fast tick; we manage pacing ourselves
        self._timer.add_callback(self._on_tick)
        self._timer.start()

    # -------------------------
    # UI
    # -------------------------
    def _build_ui(self):
        self.fig = plt.figure(figsize=(11, 7))
        self.fig.canvas.manager.set_window_title("EMG Acquisition (MCC/TEST)")
        self.fig.subplots_adjust(left=0.06, right=0.98, top=0.90, bottom=0.12, wspace=0.18, hspace=0.35)

        # Status text
        self.status_text = self.fig.text(0.06, 0.955, "", fontsize=11, ha="left")
        self.mvc_text = self.fig.text(0.62, 0.955, "", fontsize=11, ha="left")
        self.rec_text = self.fig.text(0.40, 0.955, "", fontsize=12, ha="left", color="red", weight="bold")
        self._rec_blink = False

        # Axes
        self.ax_raw1 = self.fig.add_subplot(2, 2, 1)
        self.ax_raw2 = self.fig.add_subplot(2, 2, 2)
        self.ax_env1 = self.fig.add_subplot(2, 2, 3)
        self.ax_env2 = self.fig.add_subplot(2, 2, 4)

        self._style_axes()

        # Create line artists (update with set_data only)
        (self.line_raw1,) = self.ax_raw1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_raw2,) = self.ax_raw2.plot([], [], color=COLOR_EMG2, lw=1.0)
        (self.line_env1,) = self.ax_env1.plot([], [], color=COLOR_EMG1, lw=1.0)
        (self.line_env2,) = self.ax_env2.plot([], [], color=COLOR_EMG2, lw=1.0)

        # Overlay lines (transparent other channel)
        (self.line_raw1_ol,) = self.ax_raw1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_raw2_ol,) = self.ax_raw2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env1_ol,) = self.ax_env1.plot([], [], color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        (self.line_env2_ol,) = self.ax_env2.plot([], [], color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)

        # Controls area axes
        ax_pair = self.fig.add_axes([0.06, 0.905, 0.14, 0.05])
        ax_test = self.fig.add_axes([0.22, 0.905, 0.08, 0.05])
        ax_rec = self.fig.add_axes([0.31, 0.905, 0.12, 0.05])
        ax_mvc1 = self.fig.add_axes([0.45, 0.905, 0.08, 0.05])
        ax_mvc2 = self.fig.add_axes([0.54, 0.905, 0.08, 0.05])

        ax_exp_png = self.fig.add_axes([0.70, 0.02, 0.13, 0.06])
        ax_exp_csv = self.fig.add_axes([0.85, 0.02, 0.13, 0.06])

        # Pair selector (radio buttons)
        pair_labels = [f"AI{k}-{k+1}" for k in range(7)]
        self.rb_pair = RadioButtons(ax_pair, pair_labels, active=self.pair_idx)
        self.rb_pair.on_clicked(self._on_pair_changed)

        # Test toggle
        self.btn_test = Button(ax_test, "🧪 Test")
        self.btn_test.on_clicked(self._on_toggle_test)

        # Record toggle
        self.btn_rec = Button(ax_rec, "⏺ Enregistrer")
        self.btn_rec.on_clicked(self._on_toggle_record)

        # MVC buttons
        self.btn_mvc1 = Button(ax_mvc1, "MVC 1")
        self.btn_mvc2 = Button(ax_mvc2, "MVC 2")
        self.btn_mvc1.on_clicked(lambda _evt: self._run_mvc(1))
        self.btn_mvc2.on_clicked(lambda _evt: self._run_mvc(2))

        # Export buttons
        self.btn_png = Button(ax_exp_png, "Exporter PNG")
        self.btn_csv = Button(ax_exp_csv, "Exporter CSV")
        self.btn_png.on_clicked(self._export_png)
        self.btn_csv.on_clicked(self._export_csv)

        # Close handler
        self.fig.canvas.mpl_connect("close_event", self._on_close)

    def _style_axes(self):
        for ax in (self.ax_raw1, self.ax_raw2, self.ax_env1, self.ax_env2):
            ax.set_xlim(-self.window_sec, 0.0)
            ax.grid(True, alpha=0.25)
            ax.set_xlabel("Temps (s)")

        self.ax_raw1.set_title("EMG1 brut", color=COLOR_EMG1)
        self.ax_raw2.set_title("EMG2 brut", color=COLOR_EMG2)
        self.ax_env1.set_title("EMG1 filtré (normalisé)", color=COLOR_EMG1)
        self.ax_env2.set_title("EMG2 filtré (normalisé)", color=COLOR_EMG2)

        self.ax_raw1.set_ylabel("Activité (V)")
        self.ax_raw2.set_ylabel("Activité (V)")
        self.ax_env1.set_ylabel("(%MVC)")
        self.ax_env2.set_ylabel("(%MVC)")

    def _update_status(self):
        ch1, ch2 = self._selected_channels()
        if self.test_mode:
            self.status_text.set_text(f"Mode TEST (simulé) | paire AI{ch1}-{ch2}")
        else:
            if self.mcc.available:
                self.status_text.set_text(f"Mode HARDWARE (MCC) | paire AI{ch1}-{ch2}")
            else:
                self.status_text.set_text("MCC indisponible → restez en TEST (pip install mcculw + InstaCal)")
        self.mvc_text.set_text(f"MVC1 = {self.mvc_values[0]:.2f} | MVC2 = {self.mvc_values[1]:.2f}")

    def _set_controls_enabled(self, enabled: bool):
        # Matplotlib widgets don't have a simple enable; we'll gate actions instead.
        self._controls_enabled = enabled

    # -------------------------
    # Callbacks
    # -------------------------
    def _on_pair_changed(self, label: str):
        if self.is_recording:
            return
        # label "AIx-y"
        k = int(label.split("AI")[1].split("-")[0])
        self.pair_idx = k
        self._update_status()

    def _on_toggle_test(self, _evt):
        if self.is_recording:
            return
        self.test_mode = not self.test_mode
        if self.test_mode:
            self.sim.reset_record()
            self.sim.reset_mvc()
        self._update_status()

    def _on_toggle_record(self, _evt):
        if self.is_recording:
            self._stop_recording()
        else:
            self._start_recording()

    def _on_close(self, _evt):
        self.is_recording = False

    # -------------------------
    # Recording / Streaming
    # -------------------------
    def _start_recording(self):
        # If hardware requested but not available -> refuse
        if (not self.test_mode) and (not self.mcc.available):
            self.status_text.set_text("MCC non disponible. Activez TEST.")
            return

        # Reset buffers and processors
        self.raw1[:] = 0
        self.raw2[:] = 0
        self.env1[:] = 0
        self.env2[:] = 0
        self._write_pos = 0
        self._filled = 0
        self.envproc1 = EnvelopeRMS(RMS_WIN)
        self.envproc2 = EnvelopeRMS(RMS_WIN)

        self.full_record = []  # list of blocks for later concat
        self.is_recording = True
        self.btn_rec.label.set_text("⏹ Stop")

        # Reset simulator index
        if self.test_mode:
            self.sim.reset_record()

        # Timing
        now = perf_counter()
        self._next_acq_t = now
        self._next_ui_t = now

    def _stop_recording(self):
        self.is_recording = False
        self.btn_rec.label.set_text("⏺ Enregistrer")
        self.rec_text.set_text("")
        self._rec_blink = False

        if not hasattr(self, "full_record") or len(self.full_record) == 0:
            return

        rawBuf = np.vstack(self.full_record)  # Nx2
        self.recordings_raw.append(rawBuf)

        # Final plots: show full recording (not only last window)
        self._plot_final(rawBuf)

        self.status_text.set_text(f"Enregistrement sauvegardé ({rawBuf.shape[0]/self.fs:.2f}s).")

    def _on_tick(self):
        """
        High-frequency tick; we do:
        - acquire blocks at chunk_sec pacing
        - update UI at UI_FPS
        - drift correction: if behind, resync (no accumulating lag)
        """
        if not self.is_recording:
            # still keep MVC text fresh
            self._update_status()
            return

        now = perf_counter()

        # --- Acquisition step(s): catch up if needed (drop UI frames, but don't accumulate drift) ---
        # We acquire at fixed chunk pace; if late, do multiple acquisitions without UI update.
        max_catchup_blocks = 3  # prevent runaway loops
        n_catch = 0
        while now >= self._next_acq_t and n_catch < max_catchup_blocks and self.is_recording:
            block = self._acquire_block(kind="record", n=self.chunk_pts)
            self.full_record.append(block)

            # Update ring buffers with block
            self._push_block(block)

            self._next_acq_t += self.chunk_sec
            n_catch += 1
            now = perf_counter()

        # If we're very behind, resync acquisition clock to now (prevents growing lag)
        if now - self._next_acq_t > 0.5:
            self._next_acq_t = now

        # --- UI update throttled ---
        if now >= self._next_ui_t:
            self._update_live_lines()
            self._blink_rec()
            self.fig.canvas.draw_idle()
            self._next_ui_t += self.ui_period
            # If behind, resync UI clock too
            if now - self._next_ui_t > 0.5:
                self._next_ui_t = now

    def _blink_rec(self):
        self._rec_blink = not self._rec_blink
        self.rec_text.set_text("" if self._rec_blink else "REC ●")

    def _selected_channels(self) -> Tuple[int, int]:
        ch1 = self.pair_idx
        ch2 = ch1 + 1
        return ch1, ch2

    def _acquire_block(self, kind: str, n: int) -> np.ndarray:
        ch1, ch2 = self._selected_channels()
        if self.test_mode:
            return self.sim.read_block(kind=kind, n=n)
        # hardware
        return self.mcc.read_block(ch1=ch1, ch2=ch2, n=n, fs=self.fs)

    def _push_block(self, block: np.ndarray):
        """
        Push Nx2 block into ring buffers and update streaming envelopes.
        """
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

    def _get_ring_view(self, arr: np.ndarray) -> np.ndarray:
        """
        Return buffer in chronological order (oldest..newest) for plotting.
        """
        if self._filled < self.buf_len:
            return arr[:self._filled].copy()
        p = self._write_pos
        return np.concatenate([arr[p:], arr[:p]])

    def _update_live_lines(self):
        if self._filled == 0:
            return

        raw1 = self._get_ring_view(self.raw1)
        raw2 = self._get_ring_view(self.raw2)
        env1 = self._get_ring_view(self.env1)
        env2 = self._get_ring_view(self.env2)

        # normalise envelopes to %MVC if available
        mvc1, mvc2 = self.mvc_values
        env1n = env1.copy()
        env2n = env2.copy()
        if mvc1 > 0:
            env1n = 100.0 * env1n / mvc1
        if mvc2 > 0:
            env2n = 100.0 * env2n / mvc2

        n = len(raw1)
        t = np.linspace(-self.window_sec, 0.0, n)

        # RAW
        self.line_raw1.set_data(t, raw1)
        self.line_raw2.set_data(t, raw2)
        self.line_raw1_ol.set_data(t, raw2)
        self.line_raw2_ol.set_data(t, raw1)

        # ENV
        self.line_env1.set_data(t, env1n)
        self.line_env2.set_data(t, env2n)
        self.line_env1_ol.set_data(t, env2n)
        self.line_env2_ol.set_data(t, env1n)

        # Autoscale Y (lightweight): use robust percentiles
        self._autoscale_y(self.ax_raw1, np.r_[raw1, raw2])
        self._autoscale_y(self.ax_raw2, np.r_[raw1, raw2])
        self._autoscale_y(self.ax_env1, np.r_[env1n, env2n], min_span=1.0)
        self._autoscale_y(self.ax_env2, np.r_[env1n, env2n], min_span=1.0)

        self._update_status()

    @staticmethod
    def _autoscale_y(ax, y, min_span: float = 0.1):
        y = np.asarray(y)
        if y.size == 0:
            return
        lo, hi = np.percentile(y, [2, 98])
        if not np.isfinite(lo) or not np.isfinite(hi):
            return
        if hi - lo < min_span:
            mid = 0.5 * (hi + lo)
            lo = mid - 0.5 * min_span
            hi = mid + 0.5 * min_span
        pad = 0.08 * (hi - lo)
        ax.set_ylim(lo - pad, hi + pad)

    # -------------------------
    # MVC acquisition
    # -------------------------
    def _run_mvc(self, which: int):
        if self.is_recording:
            return
        if (not self.test_mode) and (not self.mcc.available):
            self.status_text.set_text("MCC non disponible. Activez TEST.")
            return

        # Reset sim MVC index
        if self.test_mode:
            self.sim.reset_mvc()

        self.status_text.set_text(f"Mesure MVC{which} en cours (5 s)...")
        self.fig.canvas.draw_idle()

        # Collect for 5 seconds in chunks, in real time
        n_total = int(MVC_DUR_SEC * self.fs)
        buf = []

        now = perf_counter()
        next_t = now
        idx = 0

        # Prepare streaming envelope processors for display (independent)
        envproc = EnvelopeRMS(RMS_WIN)

        while idx < n_total and plt.fignum_exists(self.fig.number):
            n_this = min(self.chunk_pts, n_total - idx)

            block = self._acquire_block(kind="mvc", n=n_this)  # Nx2
            x = block[:, which - 1]  # column 0 or 1
            env = envproc.process(x)

            buf.append(x.copy())
            x_all = np.concatenate(buf)

            # live plot on appropriate axes
            t = np.arange(len(x_all)) / self.fs
            if which == 1:
                ax_raw, ax_env = self.ax_raw1, self.ax_env1
                col = COLOR_EMG1
            else:
                ax_raw, ax_env = self.ax_raw2, self.ax_env2
                col = COLOR_EMG2

            ax_raw.cla(); ax_env.cla()
            ax_raw.set_title(f"EMG{which} MVC (5s)", color=col)
            ax_env.set_title(f"EMG{which} enveloppe MVC", color=col)
            ax_raw.set_xlabel("Temps (s)"); ax_env.set_xlabel("Temps (s)")
            ax_raw.set_ylabel("Activité (V)"); ax_env.set_ylabel("(%MVC)")

            ax_raw.plot(t, x_all, color=col, lw=1.0)
            ax_env.plot(t, envproc.process(x_all), color=col, lw=1.0)
            ax_raw.set_xlim(0, MVC_DUR_SEC)
            ax_env.set_xlim(0, MVC_DUR_SEC)
            ax_raw.grid(True, alpha=0.25)
            ax_env.grid(True, alpha=0.25)

            self.fig.canvas.draw_idle()
            plt.pause(0.001)

            # pacing with drift correction
            idx += n_this
            next_t += n_this / self.fs
            delay = next_t - perf_counter()
            if delay > 0:
                time.sleep(delay)

        x_all = np.concatenate(buf) if buf else np.array([])
        if x_all.size == 0:
            self.status_text.set_text(f"MVC{which} non mesuré (pas de signal).")
            return

        # MVC = median of top 2000 abs samples (like your MATLAB)
        n_take = min(2000, x_all.size)
        top_vals = np.partition(np.abs(x_all), -n_take)[-n_take:]
        mvc_val = float(np.median(top_vals))
        self.mvc_values[which - 1] = mvc_val

        self.status_text.set_text(f"MVC{which} mesuré.")
        self._update_status()
        self.fig.canvas.draw_idle()

    # -------------------------
    # Final plots and exports
    # -------------------------
    def _plot_final(self, rawBuf: np.ndarray):
        """
        Show full raw + envelope normalised on all axes (with overlays).
        """
        emg1 = rawBuf[:, 0]
        emg2 = rawBuf[:, 1]
        t = np.arange(rawBuf.shape[0]) / self.fs

        # final envelope (same as live approach, deterministic)
        envproc1 = EnvelopeRMS(RMS_WIN)
        envproc2 = EnvelopeRMS(RMS_WIN)
        env1 = envproc1.process(emg1)
        env2 = envproc2.process(emg2)

        mvc1, mvc2 = self.mvc_values
        env1n = 100.0 * env1 / mvc1 if mvc1 > 0 else env1
        env2n = 100.0 * env2 / mvc2 if mvc2 > 0 else env2

        # Raw axes
        self.ax_raw1.cla(); self.ax_raw2.cla()
        self.ax_env1.cla(); self.ax_env2.cla()

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

        # Env axes
        self.ax_env1.plot(t, env1n, color=COLOR_EMG1, lw=1.0)
        self.ax_env1.plot(t, env2n, color=COLOR_EMG2, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_env1.set_title("EMG1 filtré (normalisé)", color=COLOR_EMG1)
        self.ax_env1.set_xlabel("Temps (s)"); self.ax_env1.set_ylabel("(%MVC)")
        self.ax_env1.grid(True, alpha=0.25)

        self.ax_env2.plot(t, env2n, color=COLOR_EMG2, lw=1.0)
        self.ax_env2.plot(t, env1n, color=COLOR_EMG1, lw=1.0, alpha=ALPHA_OVERLAY)
        self.ax_env2.set_title("EMG2 filtré (normalisé)", color=COLOR_EMG2)
        self.ax_env2.set_xlabel("Temps (s)"); self.ax_env2.set_ylabel("(%MVC)")
        self.ax_env2.grid(True, alpha=0.25)

        self.fig.canvas.draw_idle()

    def _export_png(self, _evt):
        fname = time.strftime("emg_graphs_%Y%m%d_%H%M%S.png")
        self.fig.savefig(fname, dpi=150)
        self.status_text.set_text(f"PNG exporté: {fname}")

    def _export_csv(self, _evt):
        if not self.recordings_raw:
            self.status_text.set_text("Aucun enregistrement à exporter.")
            return
        rawBuf = self.recordings_raw[-1]
        t = np.arange(rawBuf.shape[0]) / self.fs
        emg1 = rawBuf[:, 0]
        emg2 = rawBuf[:, 1]

        envproc1 = EnvelopeRMS(RMS_WIN)
        envproc2 = EnvelopeRMS(RMS_WIN)
        env1 = envproc1.process(emg1)
        env2 = envproc2.process(emg2)

        mvc1, mvc2 = self.mvc_values
        env1n = 100.0 * env1 / mvc1 if mvc1 > 0 else env1
        env2n = 100.0 * env2 / mvc2 if mvc2 > 0 else env2

        out = np.column_stack([t, emg1, emg2, env1n, env2n])
        fname = time.strftime("emg_last_%Y%m%d_%H%M%S.csv")
        header = "time_s,emg1_raw_V,emg2_raw_V,emg1_env_pctMVC,emg2_env_pctMVC"
        np.savetxt(fname, out, delimiter=",", header=header, comments="")
        self.status_text.set_text(f"CSV exporté: {fname}")


def main():
    app = EMGApp()
    plt.show()


if __name__ == "__main__":
    main()
