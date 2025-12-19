import time
import numpy as np
from collections import deque
from time import perf_counter

Fs = 2000
chunk = 200
chunk_sec = chunk / Fs
window_sec = 5
buf_len = Fs * window_sec

buf1 = deque(maxlen=buf_len)
buf2 = deque(maxlen=buf_len)

t0 = perf_counter()
next_t = t0
ui_every = 2
k = 0

while True:
    # --- simulate acquisition (replace with your generator) ---
    x1 = np.random.randn(chunk) * 0.2
    x2 = np.random.randn(chunk) * 0.2

    buf1.extend(x1.tolist())
    buf2.extend(x2.tolist())

    # --- UI update throttling ---
    k += 1
    if k % ui_every == 0:
        y1 = np.asarray(buf1)
        y2 = np.asarray(buf2)
        t = np.linspace(-window_sec, 0, len(y1))

        # update your line objects here (set_data), do NOT re-plot
        # line1.set_data(t, y1); line2.set_data(t, y2)
        # canvas.draw_idle()

    # --- real-time pacing with drift correction ---
    next_t += chunk_sec
    now = perf_counter()
    delay = next_t - now

    if delay > 0:
        time.sleep(delay)
    else:
        # we're behind: drop UI frames and resync
        next_t = now
