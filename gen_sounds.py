import wave, struct, math, os
os.makedirs("Resources", exist_ok=True)
def write(name, fn, secs=29, rate=22050):
    w = wave.open(f"Resources/{name}.wav", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, fn(i / rate))) * 24000)) for i in range(int(secs * rate)))); w.close()
sq = lambda f, t: 1 if math.sin(2 * math.pi * f * t) > 0 else -1
def beep(t):
    if t % 0.5 > 0.35: return 0
    return sq(880 if int(t / 0.5) % 2 == 0 else 1320, t)
def siren(t):
    # sine sweep 600-1400 Hz, phase integrated so it stays smooth
    return math.sin(2 * math.pi * (1000 * t - 400 / (2 * math.pi) * math.cos(2 * math.pi * t)))
def buzzer(t):
    return sq(220, t) if t % 0.5 < 0.25 else 0
def chirp(t):
    p = t % 0.12
    return sq(1500 + 8000 * p, t) if p < 0.08 and t % 1.2 < 0.6 else 0
for n, f in [("beep", beep), ("siren", siren), ("buzzer", buzzer), ("chirp", chirp)]: write(n, f)
write("silence", lambda t: 0, secs=1)
