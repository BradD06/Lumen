#!/usr/bin/env python3
"""Фоновая музыка Lumen: спокойные дорожки без авторских прав, синтезированные здесь же.

Запуск: python3 tool/make_music.py (нужны numpy и ffmpeg). Пишет assets/music/*.mp3.
Каждая дорожка зацикливается без шва: всё считается по кругу (эхо заворачивается в начало).
"""

import pathlib
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "music"


def note(name):
    """'A3' → частота."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3,
             "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def circular_echo(x, delays, gains):
    """Мягкая «комната»: несколько затухающих повторов, завёрнутых по кругу."""
    out = x.copy()
    for d, g in zip(delays, gains):
        out += g * np.roll(x, int(d * RATE), axis=0)
    return out


def lowpass(x, cutoff):
    """Простой фильтр в частотах (по кругу, шва нет)."""
    spectrum = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(x.shape[0], 1 / RATE)
    spectrum *= (1 / (1 + (freqs / cutoff) ** 4))[:, None]
    return np.fft.irfft(spectrum, n=x.shape[0], axis=0)


def highpass(x, cutoff):
    """Срез низа: на динамике телефона низкие ноты звучат как гул."""
    spectrum = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(x.shape[0], 1 / RATE)
    spectrum *= (1 / (1 + (cutoff / np.maximum(freqs, 1)) ** 4))[:, None]
    return np.fft.irfft(spectrum, n=x.shape[0], axis=0)


def evening():
    """«Тихий вечер»: редкие мягкие ноты, как фортепиано с войлоком, и едва слышный пэд.

    Раньше это был сплошной низкий аккорд: под голосом его не слышно, а в паузах между
    предложениями он звучал как гул. Теперь низа нет, а звук — отдельные затухающие ноты."""
    chords = [
        ["A3", "C4", "E4", "A4"],
        ["F3", "A3", "C4", "F4"],
        ["C4", "E4", "G4", "C5"],
        ["G3", "B3", "D4", "G4"],
        ["D4", "F4", "A4", "D5"],
        ["F3", "A3", "C4", "E4"],
        ["A3", "C4", "E4", "A4"],
        ["E3", "G#3", "B3", "E4"],
    ]
    step = 8.0
    length = int(step * len(chords) * RATE)
    t = np.arange(length) / RATE
    mix = np.zeros((length, 2))
    rng = np.random.default_rng(7)
    # Порядок нот в аккорде: вверх и обратно, с небольшой «живой» неровностью.
    pattern = [0, 1, 2, 3, 2, 1]
    for i, chord in enumerate(chords):
        begin = i * step
        for k, n in enumerate(pattern):
            at = begin + k * (step / len(pattern)) + rng.uniform(-0.04, 0.04)
            f = note(chord[n])
            dur = 3.2
            count = int(dur * RATE)
            tt = np.arange(count) / RATE
            # Мягкая атака (без щелчка) и долгое затухание; верхние гармоники гаснут быстрее.
            attack = 1 - np.exp(-tt / 0.012)
            tone = (np.sin(2 * np.pi * f * tt) * np.exp(-tt / 1.1)
                    + 0.35 * np.sin(4 * np.pi * f * tt) * np.exp(-tt / 0.45)
                    + 0.12 * np.sin(6 * np.pi * f * tt) * np.exp(-tt / 0.25))
            tone *= attack * rng.uniform(0.75, 1.0)
            side = 0.5 + 0.25 * np.sin(k + i)
            idx = (int(at * RATE) + np.arange(count)) % length
            mix[idx, 0] += tone * (1 - side)
            mix[idx, 1] += tone * side
        # Тихий пэд того же аккорда, чтобы ноты не висели в пустоте.
        center = begin + step / 2
        dist = (t - center + length / RATE / 2) % (length / RATE) - length / RATE / 2
        env = np.exp(-0.5 * (dist / (step * 0.45)) ** 2) * 0.08
        for name in chord:
            f = note(name)
            mix += (env * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)))[:, None] / len(chord)
    mix = highpass(mix, 180)
    mix = lowpass(mix, 3500)
    mix = circular_echo(mix, [0.29, 0.43, 0.71, 1.07], [0.3, 0.22, 0.15, 0.1])
    return mix


def rain():
    """«Дождь»: шум капель за окном."""
    seconds = 64
    length = seconds * RATE
    rng = np.random.default_rng(11)
    noise = rng.standard_normal((length, 2))
    # Розовый оттенок: 1/f в частотах.
    spectrum = np.fft.rfft(noise, axis=0)
    freqs = np.fft.rfftfreq(length, 1 / RATE)
    shape = 1 / np.sqrt(np.maximum(freqs, 30))
    shape *= 1 / (1 + (freqs / 5000) ** 2)
    shape *= 1 - np.exp(-freqs / 200)
    spectrum *= shape[:, None]
    hiss = np.fft.irfft(spectrum, n=length, axis=0)
    hiss /= np.abs(hiss).max()
    t = np.arange(length) / RATE
    swell = 0.8 + 0.2 * np.sin(2 * np.pi * t / seconds * 3)
    mix = hiss * swell[:, None] * 0.6
    # Отдельные капли: короткие мягкие щелчки.
    drop = np.zeros((length, 2))
    for _ in range(seconds * 9):
        at = rng.integers(0, length)
        side = rng.uniform(0.2, 0.8)
        f = rng.uniform(1800, 4200)
        n = int(0.03 * RATE)
        tt = np.arange(n) / RATE
        click = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 140) * rng.uniform(0.05, 0.2)
        idx = (at + np.arange(n)) % length
        drop[idx, 0] += click * (1 - side)
        drop[idx, 1] += click * side
    mix += drop
    # Без низкого гула: на телефоне он слышен в паузах голоса как помеха.
    return highpass(circular_echo(mix, [0.05, 0.11], [0.3, 0.15]), 150)


def write(name, samples):
    samples = samples / np.abs(samples).max() * 0.7
    pcm = (samples * 32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "track.wav"
        with wave.open(str(path), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        target = OUT / f"{name}.mp3"
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(path), "-codec:a", "libmp3lame",
             "-b:a", "96k", str(target)],
            check=True,
        )
        print(target, target.stat().st_size // 1024, "КБ")


if __name__ == "__main__":
    write("evening", evening())
    write("rain", rain())
