"""Synthesizes WakeUp's built-in alarm sounds.

Every sound is generated from scratch here (no recordings, no samples), so the
output is original work released under CC0. Run from the repository root:

    python3 scripts/gen_sounds.py

Writes 14 alarm sounds plus a silent loop to WakeUp/Resources/AlarmSounds/. Each alarm
sound is 20 seconds long: iOS plays notification and alarm sounds only if they
are 30 seconds or shorter.
"""
import array
import math
import os
import random
import wave

RATE = 22050
SECONDS = 20
OUT = os.path.join("WakeUp", "Resources", "AlarmSounds")
TAU = 2 * math.pi


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.89 / peak
    data = array.array("h", (int(max(-1.0, min(1.0, s * scale)) * 32767) for s in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def buffer(seconds=SECONDS):
    return [0.0] * int(seconds * RATE)


def add_tone(buf, start, length, partials, decay, attack=0.004, gain=1.0):
    """Adds a struck tone: partials is a list of (frequency, amplitude)."""
    s0 = int(start * RATE)
    n = min(int(length * RATE), len(buf) - s0)
    for i in range(max(0, n)):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t * decay)
        v = 0.0
        for f, a in partials:
            v += a * math.sin(TAU * f * t)
        buf[s0 + i] += v * env * gain


def add_beep(buf, start, length, freq, gain=1.0, harmonics=((1, 1.0), (3, 0.25))):
    s0 = int(start * RATE)
    n = min(int(length * RATE), len(buf) - s0)
    fade = int(0.004 * RATE)
    for i in range(max(0, n)):
        env = min(1.0, i / fade, (n - i) / fade)
        t = i / RATE
        buf[s0 + i] += gain * env * sum(a * math.sin(TAU * freq * h * t) for h, a in harmonics)


def bell(f0):
    return [(f0, 1.0), (f0 * 2.0, 0.5), (f0 * 2.76, 0.35), (f0 * 5.4, 0.15)]


def classic_bell():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        add_tone(b, t, 1.6, bell(880), 3.5)
        add_tone(b, t + 0.5, 1.6, bell(660), 3.5)
        t += 1.2
    return b


def digital_beep():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        for k in range(4):
            add_beep(b, t + k * 0.24, 0.12, 1000)
        t += 1.5
    return b


def double_beep():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        add_beep(b, t, 0.1, 1400)
        add_beep(b, t + 0.18, 0.1, 1400)
        t += 0.9
    return b


def retro_alarm():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        k = 0.0
        while k < 2.0:  # a hammer hitting two bells about 22 times a second
            add_tone(b, t + k, 0.12, bell(1250 if int(k * 22) % 2 else 1180), 18, gain=0.6)
            k += 1 / 22
        t += 3.0
    return b


def gentle_chimes():
    b = buffer()
    rng = random.Random(7)
    notes = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    t = 0.0
    while t < SECONDS - 0.2:
        loud = 0.35 + 0.65 * (t / SECONDS)  # gets louder over time
        f = rng.choice(notes)
        add_tone(b, t, 3.0, [(f, 1.0), (f * 3.01, 0.12)], 1.4, attack=0.01, gain=loud)
        t += 0.6
    return b


def morning_birds():
    b = buffer()
    rng = random.Random(11)
    t = 0.2
    while t < SECONDS - 0.5:
        base = rng.uniform(2800, 4200)
        for k in range(rng.randint(2, 5)):
            s0 = int((t + k * 0.11) * RATE)
            n = int(0.07 * RATE)
            for i in range(n):
                if s0 + i >= len(b):
                    break
                x = i / n
                f = base + 1500 * x + 300 * math.sin(TAU * 30 * x)
                b[s0 + i] += math.sin(TAU * f * i / RATE) * math.sin(math.pi * x) * 0.8
        t += rng.uniform(0.6, 1.4)
    return b


def rain_and_chimes():
    b = buffer()
    rng = random.Random(3)
    low = 0.0
    for i in range(len(b)):  # soft filtered noise
        low += 0.08 * (rng.uniform(-1, 1) - low)
        b[i] = low * 0.9
    t = 0.5
    notes = [659.25, 783.99, 987.77, 1174.66]
    while t < SECONDS:
        add_tone(b, t, 2.5, [(rng.choice(notes), 1.0)], 1.6, attack=0.01, gain=0.5)
        t += 1.6
    return b


def rising_tones():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        s0 = int(t * RATE)
        n = int(1.5 * RATE)
        loud = 0.4 + 0.6 * (t / SECONDS)
        phase = 0.0
        for i in range(n):
            if s0 + i >= len(b):
                break
            x = i / n
            phase += TAU * (400 + 800 * x) / RATE
            b[s0 + i] += math.sin(phase) * min(1, x * 20, (1 - x) * 20) * loud
        t += 2.0
    return b


def synth_pulse():
    b = buffer()
    notes = [220.0, 261.63, 329.63, 440.0, 329.63, 261.63]
    step = 0.25
    k = 0
    t = 0.0
    while t < SECONDS:
        f = notes[k % len(notes)]
        add_tone(b, t, 0.22, [(f * h, 1 / h) for h in range(1, 7)], 9, attack=0.003)
        t += step
        k += 1
    return b


def urgent_buzzer():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        add_beep(b, t, 0.4, 180, harmonics=[(h, 1 / h) for h in range(1, 12, 2)])
        t += 0.6
    return b


def fast_digital():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        for k in range(8):
            add_beep(b, t + k * 0.1, 0.05, 2400, harmonics=((1, 1.0),))
        t += 1.1
    return b


def deep_bell():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        add_tone(b, t, 3.0, bell(220), 1.2, attack=0.006)
        t += 2.5
    return b


def soft_piano():
    b = buffer()
    chords = [[261.63, 329.63, 392.0, 523.25], [220.0, 261.63, 329.63, 440.0],
              [174.61, 220.0, 261.63, 349.23], [196.0, 246.94, 293.66, 392.0]]
    t = 0.0
    k = 0
    while t < SECONDS:
        for j, f in enumerate(chords[k % 4]):
            partials = [(f, 1.0), (f * 2.003, 0.45), (f * 3.01, 0.2), (f * 4.02, 0.08)]
            add_tone(b, t + j * 0.3, 2.4, partials, 2.2, attack=0.006, gain=0.8)
        t += 1.6
        k += 1
    return b


def rising_beeps():
    b = buffer()
    t = 0.0
    while t < SECONDS:
        x = t / SECONDS
        add_beep(b, t, 0.08, 1200 + 600 * x, gain=0.3 + 0.7 * x)
        t += 0.6 - 0.45 * x  # beeps get closer together
    return b


SOUNDS = {
    "classic-bell": classic_bell,
    "digital-beep": digital_beep,
    "double-beep": double_beep,
    "retro-alarm": retro_alarm,
    "gentle-chimes": gentle_chimes,
    "morning-birds": morning_birds,
    "rain-chimes": rain_and_chimes,
    "rising-tones": rising_tones,
    "synth-pulse": synth_pulse,
    "urgent-buzzer": urgent_buzzer,
    "fast-digital": fast_digital,
    "deep-bell": deep_bell,
    "soft-piano": soft_piano,
    "rising-beeps": rising_beeps,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, make in SOUNDS.items():
        write(name, make())
        print("wrote", name)
    with wave.open(os.path.join(OUT, "silence.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"\x00\x00" * RATE)
    print("wrote silence")
