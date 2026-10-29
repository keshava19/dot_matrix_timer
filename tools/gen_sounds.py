#!/usr/bin/env python3
"""Generate the two sound effects for the dot-matrix timer.

Usage:  python3 tools/gen_sounds.py [output_dir]   (default: assets/sounds)
Needs:  numpy

start.wav  ~0.14 s  soft E5 blip, quiet confirmation (peak about -12 dBFS)
end.wav    ~3.2 s   gentle ascending E major chime, E5 - G#5 - B5 - E6 (peak about -3 dBFS)

Both are 16-bit, 44.1 kHz, mono. Everything is synthesised, so there is no
third-party licence to track.
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
rng = np.random.default_rng(7)  # fixed seed: reproducible output


def bell(freq, dur, decay, amp=1.0):
    """Soft glockenspiel/marimba-like tone: a few decaying partials."""
    t = np.arange(int(SR * dur)) / SR
    partials = [(1.0, 1.00, 1.0), (2.0, 0.35, 1.6), (3.0, 0.12, 2.4), (4.16, 0.06, 3.5)]
    y = np.zeros_like(t)
    for ratio, a, d in partials:  # (frequency ratio, amplitude, decay multiplier)
        y += a * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-decay * d * t)
    attack = np.minimum(1.0, t / 0.006)  # 6 ms attack: no click
    release = np.minimum(1.0, (dur - t) / 0.25)  # taper the last 250 ms: no click when the note is cut off
    return amp * y * attack * release


def place(buf, tone, start_s):
    i = int(start_s * SR)
    buf[i:i + len(tone)] += tone[:len(buf) - i]


def reverb(x, seconds=0.9, wet=0.16):
    """Tiny room: convolve with exponentially decaying noise (FFT)."""
    n = int(SR * seconds)
    ir = rng.standard_normal(n) * np.exp(-6.0 * np.arange(n) / n)
    ir /= np.abs(ir).sum()
    size = 1 << (len(x) + n).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    y *= np.abs(x).max() / (np.abs(y).max() + 1e-9)
    return (1 - wet) * x + wet * y


def finish(x, peak_db, fade_out_s):
    x = x - x.mean()
    n = int(SR * fade_out_s)
    x[-n:] *= np.linspace(1, 0, n) ** 2  # click-free tail
    x *= 10 ** (peak_db / 20) / np.abs(x).max()
    return x


def write_wav(path, x):
    pcm = np.clip(x, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((pcm * 32767).astype("<i2").tobytes())


def make_start():
    x = bell(659.25, 0.14, decay=22.0)  # E5, very short
    return finish(x, peak_db=-12.0, fade_out_s=0.03)


def make_end():
    buf = np.zeros(int(SR * 3.2))
    # E5, G#5, B5, E6: ascending E major, 0.26 s apart; the last note rings longest.
    for k, (f, amp) in enumerate([(659.25, 0.85), (830.61, 0.90), (987.77, 0.95), (1318.51, 1.0)]):
        place(buf, bell(f, 2.6, decay=1.7, amp=amp), 0.05 + 0.26 * k)
    buf = reverb(buf)
    return finish(buf, peak_db=-3.0, fade_out_s=0.35)


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/sounds")
    out.mkdir(parents=True, exist_ok=True)
    write_wav(out / "start.wav", make_start())
    write_wav(out / "end.wav", make_end())
    print("wrote", out / "start.wav", "and", out / "end.wav")
