#!/usr/bin/env python3
"""Generate the two sound effects for the dot-matrix timer.

Usage:  python3 tools/gen_sounds.py [output_dir]   (default: assets/sounds)
Needs:  numpy

start.wav  ~0.14 s  soft E5 blip, quiet confirmation (peak about -12 dBFS)
end.wav    ~7.2 s   gentle ascending E major chime, E5 - G#5 - B5 - E6, played twice,
                    4 s apart (each chime peaks at about -3 dBFS). The repeats start on
                    flash peaks of the 1 Hz end-of-timer flash (0 s and 4 s).

Both are 16-bit, 44.1 kHz, mono. Everything is synthesised, so there is no
third-party licence to track.
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
END_REPEATS = 2        # how many times the chime plays
END_INTERVAL_S = 4.0   # start-to-start spacing (chime is 3.2 s, so 0.8 s of silence between)
END_FLASH_S = 8.0      # length of the app's flash phase; the file must fit inside it
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


def make_chime():
    """One chime, 3.2 s, peak -3 dBFS, with its own click-free tail."""
    buf = np.zeros(int(SR * 3.2))
    # E5, G#5, B5, E6: ascending E major, 0.26 s apart; the last note rings longest.
    for k, (f, amp) in enumerate([(659.25, 0.85), (830.61, 0.90), (987.77, 0.95), (1318.51, 1.0)]):
        place(buf, bell(f, 2.6, decay=1.7, amp=amp), 0.26 * k)  # first note at 0.0 s: onset lands on the flash peak
    buf = reverb(buf)
    return finish(buf, peak_db=-3.0, fade_out_s=0.35)


def make_end():
    chime = make_chime()
    chime_s = len(chime) / SR
    assert END_INTERVAL_S >= chime_s, "chimes would overlap"
    total_s = (END_REPEATS - 1) * END_INTERVAL_S + chime_s
    if total_s > END_FLASH_S:
        print(f"WARNING: end.wav is {total_s:.1f} s, longer than the {END_FLASH_S:.0f} s flash phase")
    out = np.zeros(int(round(total_s * SR)))
    for k in range(END_REPEATS):
        i = int(round(k * END_INTERVAL_S * SR))
        out[i:i + len(chime)] += chime  # no re-normalising: each chime keeps its own level
    return out


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/sounds")
    out.mkdir(parents=True, exist_ok=True)
    write_wav(out / "start.wav", make_start())
    write_wav(out / "end.wav", make_end())
    print("wrote", out / "start.wav", "and", out / "end.wav")
