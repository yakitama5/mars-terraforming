#!/usr/bin/env python3
"""未来序章の40秒BGMを、外部音源を使わず決定的に合成する。

開発時だけ Python 3.12 / NumPy 2.3.5 を使う。ゲーム実行時の依存ではない。
再生成: python3 tools/generate_opening_music.py
既存WAVの検査: python3 tools/generate_opening_music.py --verify
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import wave

import numpy as np


RATE = 44100
DURATION = 40.0
SEED = 2026101601
SAMPLES = round(RATE * DURATION)
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/opening_music.wav"

# 120 BPM、4/4、20小節。半拍のゆったりした流れで、4小節ごとに章が変わる。
# 低い根音は別のベースへ分け、中声は滑らかに移動する開離配置を使う。
# (根音MIDI、和声音MIDI、編成の強さ)
HARMONY = [
    (38, (50, 57, 62, 64, 66), 0.60),  # 0: 都市 / Dadd9
    (37, (49, 57, 61, 64, 69), 0.64),  # A/C#
    (35, (47, 54, 57, 62, 66), 0.70),  # Bm7
    (43, (50, 55, 59, 62, 66), 0.76),  # Gmaj7
    (38, (50, 57, 62, 64, 66), 0.88),  # 8: 打上 / Dadd9
    (40, (52, 55, 59, 62, 66), 0.96),  # Em9
    (43, (50, 55, 59, 62, 69), 1.00),  # Gadd9
    (45, (52, 57, 59, 61, 64), 0.90),  # Aadd9
    (35, (47, 54, 57, 61, 66), 0.52),  # 16: 月 / Bm9
    (43, (50, 55, 59, 62, 66), 0.48),  # Gmaj7
    (38, (50, 57, 61, 64, 66), 0.55),  # Dmaj9
    (45, (52, 57, 59, 61, 66), 0.58),  # A6/9
    (40, (52, 55, 59, 62, 66), 0.67),  # 24: 探査 / Em9
    (43, (50, 55, 59, 62, 69), 0.72),  # Gadd9
    (35, (47, 54, 57, 62, 66), 0.79),  # Bm7
    (45, (52, 57, 59, 62, 64), 0.83),  # Asus4(add9)
    (43, (50, 55, 59, 62, 66), 0.88),  # 32: 移住 / Gmaj7
    (45, (52, 57, 59, 61, 64), 0.84),  # Aadd9
    (38, (50, 57, 61, 64, 66), 0.75),  # Dmaj9、最後は長く保持
]


def frequency(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def smoothstep(value: np.ndarray) -> np.ndarray:
    value = np.clip(value, 0.0, 1.0)
    return value * value * (3.0 - 2.0 * value)


def envelope(time: np.ndarray, duration: float, attack: float, release: float) -> np.ndarray:
    return smoothstep(time / attack) * smoothstep((duration - time) / release)


def filtered_noise(
    count: int, rng: np.random.Generator, low: float, high: float
) -> np.ndarray:
    noise = rng.normal(0.0, 1.0, count)
    spectrum = np.fft.rfft(noise)
    bins = np.fft.rfftfreq(count, 1.0 / RATE)
    curve = 1.0 / np.sqrt(1.0 + (bins / high) ** 8)
    if low:
        curve *= 1.0 - 1.0 / np.sqrt(1.0 + (bins / low) ** 8)
    result = np.fft.irfft(spectrum * curve, n=count)
    return result / max(float(np.std(result)), 1e-9)


def pad(midi: int, duration: float, rng: np.random.Generator, strings: bool) -> np.ndarray:
    """微小に揺れる複数奏者と、倍音ごとの減衰で平坦な電子音を避ける。"""
    time = np.arange(round(duration * RATE), dtype=np.float64) / RATE
    result = np.zeros((len(time), 2), dtype=np.float64)
    base = frequency(midi)
    # 同じ左右信号を複製せず、各奏者を小さく離して配置する。
    for detune, pan in [(-4.1, -0.73), (-0.5, -0.12), (3.8, 0.68)]:
        pitch = base * 2.0 ** (detune / 1200.0)
        phase = 2 * np.pi * pitch * time
        phase += 0.16 * np.sin(2 * np.pi * 0.23 * time + rng.uniform(0, 6.28))
        phase += 0.018 * np.sin(2 * np.pi * 4.9 * time + rng.uniform(0, 6.28))
        voice = np.zeros(len(time), dtype=np.float64)
        for harmonic in range(1, 15 if strings else 10):
            rolloff = math.exp(-((base * harmonic) / (1650 if strings else 1100)) ** 2)
            amount = rolloff / harmonic ** (1.10 if strings else 1.65)
            initial = rng.uniform(0.0, 2 * np.pi)
            voice += amount * np.sin(harmonic * phase + initial)
        voice *= 0.94 + 0.06 * np.sin(2 * np.pi * 0.67 * time + detune)
        angle = (pan + 1) * np.pi / 4
        result[:, 0] += voice * math.cos(angle)
        result[:, 1] += voice * math.sin(angle)
    attack, release = (0.58, 0.95) if strings else (0.85, 1.25)
    result *= envelope(time, duration, attack, release)[:, None]
    return result * (0.18 if strings else 0.20)


def felt_key(midi: int, duration: float, rng: np.random.Generator) -> np.ndarray:
    """不調和な弦の倍音と柔らかい打鍵。録音ピアノの再現ではない。"""
    time = np.arange(round(duration * RATE), dtype=np.float64) / RATE
    base = frequency(midi)
    result = np.zeros(len(time), dtype=np.float64)
    for harmonic in range(1, 11):
        partial = base * harmonic * math.sqrt(1 + 0.00008 * harmonic * harmonic)
        decay = np.exp(-time / (2.2 / (1 + harmonic * 0.19)))
        amplitude = math.exp(-partial / 2600) / harmonic**1.65
        # 二本の弦の緩いビート。強いアタックを作らない。
        result += amplitude * decay * (
            np.sin(2 * np.pi * partial * time)
            + 0.42 * np.sin(2 * np.pi * partial * 1.0008 * time + 0.12)
        )
    felt = filtered_noise(len(time), rng, 250, 1600)
    result += felt * np.exp(-time / 0.035) * 0.018
    return result * envelope(time, duration, 0.012, 0.36) * 0.26


def bell(midi: int, duration: float) -> np.ndarray:
    time = np.arange(round(duration * RATE), dtype=np.float64) / RATE
    result = np.zeros(len(time), dtype=np.float64)
    for ratio, strength, decay in [(1, 1, 2.5), (2.01, 0.24, 1.9), (2.74, 0.11, 0.8), (4.08, 0.04, 0.45)]:
        result += strength * np.sin(2 * np.pi * frequency(midi) * ratio * time) * np.exp(-time / decay)
    return result * envelope(time, duration, 0.035, 0.8) * 0.2


def bass(midi: int, duration: float) -> np.ndarray:
    time = np.arange(round(duration * RATE), dtype=np.float64) / RATE
    phase = 2 * np.pi * frequency(midi) * time
    result = np.sin(phase) + 0.18 * np.sin(phase * 2) + 0.07 * np.sin(phase * 3)
    return result * envelope(time, duration, 0.24, 0.65) * 0.20


def drum(rng: np.random.Generator, soft: bool = False) -> np.ndarray:
    duration = 1.1 if not soft else 0.45
    time = np.arange(round(duration * RATE), dtype=np.float64) / RATE
    # 柔らかな膜音。ノイズに短い減衰を付け、硬いクリックは入れない。
    phase = 2 * np.pi * (62 * time + 28 * 0.045 * (1 - np.exp(-time / 0.045)))
    result = np.sin(phase) * np.exp(-time / 0.22)
    result += 0.32 * np.sin(phase * 1.48) * np.exp(-time / 0.12)
    result += filtered_noise(len(time), rng, 60, 400) * np.exp(-time / 0.08) * 0.12
    if soft:
        result *= 0.40
    return result * envelope(time, duration, 0.014, 0.14) * 0.33


def add(bus: np.ndarray, signal: np.ndarray, start: float, gain: float, pan: float = 0) -> None:
    offset = round(start * RATE)
    count = min(len(signal), len(bus) - offset)
    if count <= 0:
        return
    if signal.ndim == 1:
        angle = (pan + 1) * np.pi / 4
        bus[offset : offset + count, 0] += signal[:count] * gain * math.cos(angle)
        bus[offset : offset + count, 1] += signal[:count] * gain * math.sin(angle)
    else:
        bus[offset : offset + count] += signal[:count] * gain


def hall(signal: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """左右で異なる初期反射＋密な暗い残響。外部のIR音源も使わない。"""
    count = round(2.8 * RATE)
    time = np.arange(count) / RATE
    impulse = filtered_noise(count, rng, 150, 4200)
    impulse *= np.exp(-time * 3.1) * smoothstep((time - 0.025) / 0.07)
    impulse *= 0.36 / max(float(np.sqrt(np.sum(impulse * impulse))), 1e-9)
    for seconds, level in [(0.031, 0.13), (0.047, -0.09), (0.071, 0.07), (0.113, 0.055)]:
        impulse[round((seconds + rng.uniform(-0.004, 0.004)) * RATE)] += level
    size = 1 << (len(signal) + count - 2).bit_length()
    return np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(impulse, size), size)[: len(signal)]


def render() -> np.ndarray:
    rng = np.random.default_rng(SEED)
    pads = np.zeros((SAMPLES, 2), dtype=np.float64)
    details = np.zeros_like(pads)
    foundation = np.zeros_like(pads)

    for bar, (root, notes, energy) in enumerate(HARMONY):
        at = bar * 2.0
        chapter = bar // 4
        length = 4.0 if bar == len(HARMONY) - 1 else 2.85
        for index, note in enumerate(notes):
            # 最上声を控え、語りのある中高域に一定の余白を残す。
            gain = energy * (0.27 if index == 4 else 0.40)
            add(pads, pad(note, length, rng, strings=False), at, gain)
            if chapter in (1, 4):
                add(pads, pad(note, length, rng, strings=True), at, gain * 0.42)
        add(foundation, bass(root, length), at, energy * (0.76 if chapter == 1 else 0.56))

        if chapter in (0, 1, 3):
            # 設計が一つずつ積み上がる、小さな鍵盤の反復。
            pattern = [notes[1], notes[3], notes[2], notes[4]]
            for step, note in enumerate(pattern):
                if chapter == 0 and step % 2:
                    continue
                at_note = at + 0.18 + step * 0.5 + rng.uniform(-0.012, 0.012)
                gain = energy * (0.17 if chapter == 1 else 0.21)
                add(details, felt_key(note, 2.4, rng), at_note, gain, pan=(-0.28 if step % 2 else 0.28))

    # 章をまたいで戻ってくる、短い独自の旋律。語りの隙間に置く。
    melody = [
        (0.8, 69, 0.25), (2.7, 66, 0.22), (4.8, 64, 0.22), (6.2, 62, 0.24),
        (8.5, 66, 0.30), (10.3, 69, 0.31), (12.5, 71, 0.31), (14.2, 69, 0.27),
        (17.0, 66, 0.20), (20.8, 64, 0.20),
        (24.8, 66, 0.25), (26.5, 69, 0.26), (28.6, 66, 0.24), (30.4, 64, 0.25),
        (32.6, 66, 0.30), (34.3, 64, 0.25), (36.2, 62, 0.30),
    ]
    for at, note, gain in melody:
        add(details, felt_key(note, 3.5, rng), at, gain, pan=-0.10)
    for at, note, gain in [(1.0, 74, 0.12), (9.0, 78, 0.14), (16.4, 78, 0.16), (21.0, 76, 0.11), (32.3, 78, 0.14), (36.1, 74, 0.16)]:
        add(details, bell(note, 3.8), at, gain, pan=0.38)

    for at in [8.0, 10.0, 12.0, 14.0, 24.0, 26.0, 28.0, 30.0, 32.0, 34.0]:
        add(foundation, drum(rng), at, 0.42 if at < 16 else 0.26)
        if at < 16 or 24 <= at < 32:
            add(foundation, drum(rng, soft=True), at + 1.5, 0.23, pan=0.15)

    # 打上直前と移住直前の空気感。効果音のロケット音とは混同しない。
    for at, length, gain in [(5.0, 3.2, 0.012), (29.0, 3.2, 0.009)]:
        time = np.arange(round(length * RATE)) / RATE
        swell = filtered_noise(len(time), rng, 160, 950)
        swell *= np.sin(np.pi * time / length) ** 2
        add(details, swell, at, gain, pan=-0.25)

    wet = np.zeros_like(pads)
    for channel in range(2):
        send = pads[:, channel] * 0.64 + details[:, channel] * 0.85
        send += details[:, 1 - channel] * 0.18
        wet[:, channel] = hall(send, rng)
    mixed = pads + details + foundation + wet * 0.66

    # 語りの明瞭さを守る広い凹みと、不要な低域/極端な高域の除去。
    bins = np.fft.rfftfreq(SAMPLES, 1.0 / RATE)
    curve = (1 - np.exp(-((bins / 35) ** 4))) / np.sqrt(1 + (bins / 7000) ** 6)
    curve *= 1 - 0.46 * np.exp(-0.5 * (np.log2(np.maximum(bins, 1) / 2300) / 0.72) ** 2)
    for channel in range(2):
        mixed[:, channel] = np.fft.irfft(np.fft.rfft(mixed[:, channel]) * curve, SAMPLES)

    time = np.arange(SAMPLES) / RATE
    mixed *= (smoothstep(time / 1.2) * smoothstep((39.95 - time) / 3.6))[:, None]
    mixed -= np.mean(mixed, axis=0)
    # 音量はナレーションの下に置く素材として -24 dBFS RMSへ。
    rms = float(np.sqrt(np.mean(mixed * mixed)))
    mixed *= 10 ** (-24 / 20) / rms
    peak = float(np.max(np.abs(mixed)))
    if peak > 10 ** (-6 / 20):
        mixed *= 10 ** (-6 / 20) / peak
    # 16bit量子化前のTPDFディザ。末尾50msは完全な無音にする。
    mixed += (rng.random(mixed.shape) - rng.random(mixed.shape)) / 65536.0
    mixed[: round(RATE * 0.004)] = 0
    mixed[round(RATE * 39.95) :] = 0
    return mixed


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def decibels(value: float) -> float:
    return round(20 * math.log10(max(value, 1e-12)), 3)


def verify(path: Path) -> dict:
    with wave.open(str(path), "rb") as source:
        params = source.getparams()
        assert params.nchannels == 2 and params.sampwidth == 2
        assert params.framerate == RATE and params.nframes == SAMPLES
        samples = np.frombuffer(source.readframes(params.nframes), dtype="<i2").reshape(-1, 2).astype(np.float64) / 32768
    assert np.isfinite(samples).all()
    peak = float(np.max(np.abs(samples)))
    assert peak <= 10 ** (-5.99 / 20), "ヘッドルーム不足"
    assert not np.any(samples[-round(0.05 * RATE) :]), "残響の末尾が無音でない"
    # 4倍の帯域制限補間でもクリップしないことを確認。LUFS測定ではない。
    oversampled_peak = max(
        float(np.max(np.abs(np.fft.irfft(np.fft.rfft(samples[:, channel]), len(samples) * 4) * 4)))
        for channel in range(2)
    )
    assert oversampled_peak < 10 ** (-5.9 / 20)
    chapter_rms = []
    for chapter in range(5):
        part = samples[chapter * 8 * RATE : (chapter + 1) * 8 * RATE]
        chapter_rms.append(decibels(float(np.sqrt(np.mean(part * part)))))
    return {
        "file": str(path),
        "duration_seconds": params.nframes / params.framerate,
        "sample_rate": params.framerate,
        "channels": params.nchannels,
        "pcm_bits": params.sampwidth * 8,
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "sample_peak_dbfs": decibels(peak),
        "fourfold_peak_dbfs": decibels(oversampled_peak),
        "rms_dbfs": decibels(float(np.sqrt(np.mean(samples * samples)))),
        "chapter_rms_dbfs": chapter_rms,
        "stereo_correlation": round(float(np.corrcoef(samples.T)[0, 1]), 3),
        "last_50ms_silent": True,
        "numpy_version": np.__version__,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify", action="store_true", help="生成せず既存WAVを検査する")
    args = parser.parse_args()
    if not args.verify:
        write_wav(args.output, render())
    print(json.dumps(verify(args.output), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
