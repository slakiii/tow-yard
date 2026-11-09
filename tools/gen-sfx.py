#!/usr/bin/env python3
"""Regenerate assets/sfx/*.wav from parameters. numpy only, deterministic.

The pack is synthesised rather than sampled so every cue is a number you can
tune: a bump is louder because its gain curve says so, not because somebody
picked a different recording. Nothing here is a licensed asset.

Loops are WAV on purpose. Vorbis carries encoder padding, which the decoder
cannot cancel, so a 0.5 s engine loop acquires a click at every splice; the two
looping cues stay uncompressed (44 KB and 62 KB) and the one-shots do not care.

    python3 tools/gen-sfx.py          # rewrites assets/sfx/
"""
import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")


def tt(dur):
    return np.arange(int(round(dur * SR))) / SR


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def fft_shape(x, lo=None, hi=None, order=2, peak=None, q=2.0):
    """Zero-phase magnitude shaping. A periodic signal stays periodic, so this
    keeps a loop seamless where a stateful IIR filter would not."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    m = np.ones_like(f)
    if lo:
        m *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
    if hi:
        m *= 1.0 / (1.0 + (f / hi) ** (2 * order))
    if peak:  # one resonant bump: the body of a grind or a scuff
        m *= 1.0 + (q - 1.0) * np.exp(-0.5 * (np.log(np.maximum(f, 1e-9) / peak) / 0.18) ** 2)
    return np.fft.irfft(X * m, n)


def sine(t, f):
    return np.sin(2 * np.pi * f * t)


def sweep(t, f0, f1, curve=1.0):
    f = f0 + (f1 - f0) * (t / t[-1]) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def pad(x, dur):
    n = int(round(dur * SR))
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def bell(t, f, decay, partials=((1.0, 1.0), (2.76, 0.35), (5.4, 0.12))):
    s = np.zeros(len(t))
    for mult, amp in partials:
        s += amp * sine(t, f * mult) * np.exp(-t / (decay / mult ** 0.5))
    s *= np.clip(t / 0.004, 0, 1)
    return s


def click(n, seed, bright=4000, decay=0.004):
    x = noise(n, seed)
    x = fft_shape(x, lo=300, hi=bright, order=1)
    return x * np.exp(-np.arange(n) / (decay * SR))


# --------------------------------------------------------------- cue by cue
def engine_idle():
    """Loop. Additive firing chug + circular noise on a 2 Hz grid: 0.5 s holds
    whole cycles of every component, so the splice is continuous."""
    dur, f0 = 0.5, 24.0
    t = tt(dur)
    body = np.zeros(len(t))
    for k, amp in enumerate([1.0, .62, .45, .30, .22, .16, .12, .09, .07, .05, .04, .03], start=1):
        body += amp * np.sin(2 * np.pi * f0 * k * t + (k * 1.7) % (2 * np.pi))
    circ = np.fft.irfft(np.fft.rfft(noise(len(t), 1)), len(t))
    x = 0.55 * body + 0.45 * fft_shape(circ, lo=60, hi=900, order=2)
    x *= 1.0 + 0.18 * np.sin(2 * np.pi * 4.0 * t)
    x = fft_shape(x, lo=35, hi=2200, order=2)
    return x / np.abs(x).max()


def reverse_beep():
    t = tt(0.16)
    tone = np.sign(sine(t, 900)) * 0.45 + sine(t, 900) * 0.55
    e = np.clip(t / 0.006, 0, 1) * np.exp(-t / 0.045)
    return pad(fft_shape(tone * e, lo=500, hi=2400, order=2), 0.16)


def gear_clunk():
    t = tt(0.30)
    thump = sine(t, 58) * np.exp(-t / 0.075) * np.clip(t / 0.002, 0, 1)
    mech = fft_shape(noise(len(t), 7), lo=180, hi=2600, order=2) * np.exp(-t / 0.030)
    ring = (sine(t, 1630) * 0.5 + sine(t, 2470) * 0.25) * np.exp(-t / 0.10) * np.clip(t / 0.001, 0, 1)
    return pad(thump + 0.7 * mech + 0.10 * ring, 0.30)


def wall_thud():
    t = tt(0.50)
    body = sweep(t, 95, 36, curve=0.6) * np.exp(-t / 0.13) * np.clip(t / 0.0015, 0, 1)
    crunch = fft_shape(noise(len(t), 11), lo=120, hi=3200, order=2) * np.exp(-t / 0.045)
    scrape = fft_shape(noise(len(t), 12), lo=900, hi=7000, order=1) * np.exp(-t / 0.09) * 0.25
    return pad(body + 0.8 * crunch + scrape, 0.50)


def jackknife():
    """Deliberately not a thud: the cause is articulation, the fix is to
    straighten, so the sound is metal grinding rather than an impact."""
    t = tt(0.75)
    grind = fft_shape(noise(len(t), 21), lo=700, hi=3200, order=1, peak=1500, q=3.0)
    grind *= (0.55 + 0.45 * np.sin(2 * np.pi * 23 * t)) * np.exp(-t / 0.32)
    metal = sum(a * sine(t, f) for f, a in ((1234, .30), (1789, .22), (2311, .14))) * np.exp(-t / 0.28)
    groan = sweep(t, 110, 62, curve=0.8) * 0.55 * np.exp(-t / 0.20)
    x = (0.8 * grind + metal + groan) * np.clip(t / 0.004, 0, 1)
    return pad(x, 0.75)


def cone_knock():
    t = tt(0.26)
    tok = (sweep(t, 340, 210, 0.5) * 0.8 + sine(t, 740) * 0.30) * np.exp(-t / 0.045)
    x = tok * np.clip(t / 0.002, 0, 1) + 0.35 * click(len(t), 31, bright=6000, decay=0.006)
    for start, amp in ((0.055, 0.22), (0.085, 0.13), (0.130, 0.08)):  # it rattles away
        i = int(start * SR)
        x[i:] += amp * click(len(t) - i, 40 + i, bright=5000, decay=0.005)[: len(x) - i]
    return pad(x, 0.26)


def tyre_skid():
    """Loop. Loose-surface scuff, not a tyre squeal: the reverse cap is 1.8 m/s
    and squealing at walking pace is a lie. 10 Hz flutter fits 7 cycles."""
    dur = 0.7
    t = tt(dur)
    n = len(t)
    x = np.fft.irfft(np.fft.rfft(noise(n, 51)), n)
    x = fft_shape(x, lo=1100, hi=4200, order=2, peak=2100, q=4.0)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 10.0 * t)
    return fft_shape(x, lo=900, hi=5200, order=2)


def park_chime():
    t = tt(1.30)
    x = np.zeros(len(t))
    for start, amp in ((0.0, 0.35), (0.055, 0.28), (0.105, 0.22)):  # handbrake pawl
        i = int(start * SR)
        x[i:] += amp * click(len(t) - i, 61 + i, bright=5200, decay=0.0035)[: len(x) - i]
    motif = 0.55 * bell(t - 0.20, 659.25, 0.55) + 0.5 * bell(t - 0.34, 987.77, 0.75)
    motif[: int(0.20 * SR)] = 0
    return pad(x + motif, 1.30)


def star_blip():  # the game pitches this 1.0 / 1.26 / 1.5 for one to three stars
    t = tt(0.30)
    return pad(bell(t, 880.0, 0.18, partials=((1.0, 1.0), (2.0, 0.28), (3.01, 0.10))), 0.30)


def par_tick():
    """Dull woodblock: the 3-star window just closed. Must not read as a reward
    (that is star_blip) or as a menu key (1.5 kHz)."""
    t = tt(0.22)
    body = (sweep(t, 240, 200) * 0.9 + sine(t, 480) * 0.25) * np.exp(-t / 0.030)
    body *= np.clip(t / 0.0015, 0, 1)
    return pad(body + 0.35 * click(len(t), 71, bright=3000, decay=0.004), 0.22)


def ui_tick():
    t = tt(0.07)
    x = (sine(t, 1500) * 0.7 + sine(t, 3000) * 0.2) * np.exp(-t / 0.012)
    return pad(x * np.clip(t / 0.0015, 0, 1), 0.07)


def ui_confirm():
    t = tt(0.26)
    x = np.zeros(len(t))
    for start, f, amp in ((0.0, 784.0, 0.6), (0.075, 1174.7, 0.55)):
        b = bell(t - start, f, 0.22, partials=((1.0, 1.0), (2.0, 0.2)))
        b[: int(start * SR)] = 0
        x += amp * b
    return pad(x, 0.26)


# name, function, gain: gain is the cue's place in the mix, so a cone is quiet
# and a wall is the loudest thing in the pack before the game scales it.
SOUNDS = [
    ("engine_idle", engine_idle, 0.80),
    ("reverse_beep", reverse_beep, 0.75),
    ("gear_clunk", gear_clunk, 0.85),
    ("wall_thud", wall_thud, 1.00),
    ("jackknife", jackknife, 0.95),
    ("cone_knock", cone_knock, 0.70),
    ("tyre_skid", tyre_skid, 0.70),
    ("park_chime", park_chime, 0.90),
    ("star_blip", star_blip, 0.75),
    ("par_tick", par_tick, 0.65),
    ("ui_tick", ui_tick, 0.60),
    ("ui_confirm", ui_confirm, 0.75),
]


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"{'name':14s} {'dur':>5s} {'peak':>5s} {'rms':>6s}")
    for name, fn, gain in SOUNDS:
        raw = fn()
        x = raw / (np.abs(raw).max() or 1) * gain * 0.9
        write_wav(os.path.join(OUT, name + ".wav"), x)
        print(f"{name:14s} {len(x) / SR:5.2f} {np.abs(x).max():5.2f} {np.sqrt((x ** 2).mean()):6.3f}")


if __name__ == "__main__":
    main()
