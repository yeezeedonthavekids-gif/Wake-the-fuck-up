import wave, struct, math, os
os.makedirs("Resources", exist_ok=True)
def write(name, secs, fn, rate=22050):
    w = wave.open(f"Resources/{name}", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", int(fn(i / rate))) for i in range(int(secs * rate)))); w.close()
def alarm(t):
    if t % 0.5 > 0.35: return 0
    f = 880 if int(t / 0.5) % 2 == 0 else 1320
    return 24000 * (1 if math.sin(2 * math.pi * f * t) > 0 else -1)
write("alarm.wav", 29, alarm)
write("silence.wav", 1, lambda t: 0)
