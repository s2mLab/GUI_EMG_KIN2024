import unittest

import numpy as np

from EMG_GUI_diligent import (
    FS,
    overlay_alpha_for_duration,
    process_emg_offline,
    signal_quality_messages,
)


class EMGProcessingTests(unittest.TestCase):
    def test_conditioning_reduces_mains_component(self):
        t = np.arange(2 * FS) / FS
        raw = np.sin(2 * np.pi * 60 * t) + 0.2 * np.sin(2 * np.pi * 80 * t)

        filtered, envelope = process_emg_offline(raw, FS)

        raw_60 = abs(np.vdot(raw, np.exp(-2j * np.pi * 60 * t)))
        filtered_60 = abs(np.vdot(filtered, np.exp(-2j * np.pi * 60 * t)))
        self.assertEqual(envelope.shape, raw.shape)
        self.assertLess(filtered_60, 0.2 * raw_60)

    def test_quality_reports_saturation_and_mains_noise(self):
        t = np.arange(2 * FS) / FS
        raw = np.column_stack([
            np.full_like(t, 5.0),
            np.sin(2 * np.pi * 60 * t),
        ])

        messages = signal_quality_messages(raw, FS)

        self.assertTrue(any("saturation" in message for message in messages))
        self.assertIn("EMG2 bruit 60 Hz eleve", messages)

    def test_long_trials_make_comparison_overlay_more_transparent(self):
        alpha_10 = overlay_alpha_for_duration(10)
        alpha_30 = overlay_alpha_for_duration(30)

        self.assertLess(alpha_30, alpha_10)
        self.assertAlmostEqual(alpha_30, alpha_10 / 3)


if __name__ == "__main__":
    unittest.main()
