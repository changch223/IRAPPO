#!/usr/bin/env python3
"""Generate placeholder event sound effects (clang / whoosh / ping / boom / chime).

Recipes follow the prototype functions in docs/redesign/prototype/irappo-prototype-src.html.
Output: mono, 16-bit, 44.1 kHz wav, peak normalised to 0.8, written to iratappu/HIT/.
Usage: python3 tools/gen_sfx.py [output_dir]
"""
import math
import os
import random
import struct
import sys
import wave

SR = 44100
random.seed(7)  # reproducible noise


def silence(sec):
    return [0.0] * int(SR * sec)


def mix_into(dst, src, at):
    start = int(at * SR)
    if start + len(src) > len(dst):
        dst.extend([0.0] * (start + len(src) - len(dst)))
    for i, v in enumerate(src):
        dst[start + i] += v


def env(n, peak, dur_samples):
    # exponential ramp peak -> 0.001 over dur, like exponentialRampToValueAtTime
    k = math.log(0.001 / peak)
    return [peak * math.exp(k * min(i / dur_samples, 1.0)) for i in range(n)]


def tone(kind, f0, f1, peak, dur):
    n = int(SR * (dur + 0.05))
    d = int(SR * dur)
    e = env(n, peak, d)
    out = []
    phase = 0.0
    for i in range(n):
        t = min(i / d, 1.0)
        f = f0 if not f1 else f0 * (f1 / f0) ** t
        phase += 2 * math.pi * f / SR
        if kind == "sine":
            s = math.sin(phase)
        elif kind == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        elif kind == "sawtooth":
            s = 2 * ((phase / (2 * math.pi)) % 1.0) - 1
        elif kind == "triangle":
            s = 2 / math.pi * math.asin(math.sin(phase))
        else:
            s = math.sin(phase)
        out.append(s * e[i])
    return out


def biquad(samples, ftype, freq, q):
    w0 = 2 * math.pi * freq / SR
    alpha = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    if ftype == "lowpass":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif ftype == "highpass":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:  # bandpass (constant 0 dB peak gain)
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in samples:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def noise(ftype, freq, q, peak, dur):
    n = int(SR * (dur + 0.05))
    src = [random.random() * 2 - 1 for _ in range(n)]
    filt = biquad(src, ftype, freq, q)
    e = env(n, peak, int(SR * dur))
    return [filt[i] * e[i] for i in range(n)]


def normalise(samples, peak=0.8):
    m = max(abs(s) for s in samples) or 1.0
    return [s * peak / m for s in samples]


def write(path, samples):
    samples = normalise(samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def clang():
    out = silence(0.3)
    mix_into(out, tone("square", 1900, 1300, 0.07, 0.16), 0)
    mix_into(out, tone("sine", 2700, 0, 0.1, 0.22), 0)
    return out


def whoosh():
    out = silence(0.2)
    mix_into(out, noise("highpass", 2600, 0.6, 0.16, 0.14), 0)
    return out


def ping():
    out = silence(0.4)
    mix_into(out, tone("sine", 1568, 0, 0.16, 0.3), 0)
    mix_into(out, tone("sine", 2093, 0, 0.12, 0.3), 0.05)
    return out


def boom():
    out = silence(0.8)
    mix_into(out, tone("sine", 150, 30, 0.8, 0.7), 0)
    mix_into(out, noise("lowpass", 700, 0.5, 0.5, 0.45), 0)
    mix_into(out, noise("bandpass", 2000, 0.7, 0.35, 0.12), 0)
    return out


def chime():
    out = silence(1.2)
    for i, f in enumerate((523, 784, 1047)):
        mix_into(out, tone("sine", f, 0, 0.12, 0.9), i * 0.1)
    return out


def slap(pw=1.0):
    """prototype slap(): bandpass noise + low sine sweep"""
    out = silence(0.2)
    mix_into(out, noise("bandpass", 1600, 0.8, 0.42 * pw, 0.1), 0)
    mix_into(out, tone("sine", 200, 55, 0.5 * pw, 0.13), 0)
    return out


def slipper():
    out = slap(1.0)
    mix_into(out, noise("bandpass", 3200, 1.2, 0.32, 0.06), 0)
    return out


def hammer():
    out = slap(0.6)
    mix_into(out, noise("highpass", 5200, 0.7, 0.28, 0.09), 0)
    mix_into(out, tone("sine", 3100, 2300, 0.06, 0.14), 0)
    mix_into(out, tone("sine", 4200, 0, 0.04, 0.1), 0.03)
    return out


def shatter():
    out = silence(0.45)
    mix_into(out, noise("highpass", 4500, 0.6, 0.5, 0.3), 0)
    mix_into(out, tone("sine", 3600, 1800, 0.08, 0.3), 0)
    mix_into(out, tone("sine", 5200, 2600, 0.05, 0.2), 0.04)
    return out


def bolt():
    out = silence(0.5)
    mix_into(out, noise("bandpass", 1300, 0.5, 0.5, 0.22), 0)
    mix_into(out, tone("sawtooth", 95, 38, 0.3, 0.28), 0)
    mix_into(out, tone("sine", 60, 28, 0.5, 0.45), 0)   # 低頻轟鳴
    return out


def kb():
    out = silence(0.15)
    mix_into(out, noise("highpass", 4000, 1.0, 0.28, 0.025), 0)
    mix_into(out, noise("highpass", 3200, 1.0, 0.2, 0.03), 0.05)
    mix_into(out, tone("sine", 180, 90, 0.2, 0.06), 0)
    return out


def bubble():
    out = silence(0.15)
    mix_into(out, tone("sine", 900, 260, 0.3, 0.07), 0)
    return out


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "iratappu", "HIT")
    os.makedirs(dest, exist_ok=True)
    for name, fn in (("clang", clang), ("whoosh", whoosh), ("ping", ping), ("boom", boom), ("chime", chime),
                     ("slipper", slipper), ("hammer", hammer), ("shatter", shatter),
                     ("bolt", bolt), ("kb", kb), ("bubble", bubble)):
        write(os.path.join(dest, name + ".wav"), fn())
        print("wrote", name + ".wav")
