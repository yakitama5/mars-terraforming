#!/usr/bin/env python3
"""全10本の検証済みルナ音声がそろったときだけ、40秒OPとカタログを公開する。

Python 3.12 / NumPy 2.3.5を開発時だけ使用する。音声生成APIは呼ばない。
不変のハッシュ付き素材を先に保存し、catalog.jsonの置換を唯一の公開点とする。
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import tempfile
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
FRAMES = RATE * 40
OPENING_IDS = tuple(f"opening_{index:02d}" for index in range(1, 6))
GUIDE_IDS = tuple("first_run_" + name for name in (
    "placeHousing", "finishConstruction", "income", "startResearch", "researchStarted"
))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def db(value: float) -> float:
    return round(20 * math.log10(max(value, 1e-12)), 3)


def pcm(data: bytes, label: str, limit: float) -> tuple[np.ndarray, int, dict]:
    try:
        with wave.open(io.BytesIO(data), "rb") as source:
            channels = source.getnchannels()
            rate = source.getframerate()
            frames = source.getnframes()
            if (source.getcomptype() != "NONE" or source.getsampwidth() != 2
                    or channels not in (1, 2) or not 8000 <= rate <= 96000):
                raise ValueError("PCM16 mono/stereo、8〜96kHzが必要")
            if not 0.25 < frames / rate <= limit:
                raise ValueError(f"長さ{frames / rate:.4f}秒が範囲外（最大{limit}秒）")
            raw = source.readframes(frames)
            if len(raw) != frames * channels * 2:
                raise ValueError("PCMデータが途中で切れている")
    except (wave.Error, EOFError, ValueError) as error:
        raise ValueError(f"{label}: {error}") from error
    integers = np.frombuffer(raw, dtype="<i2").reshape(-1, channels)
    peak_integer = int(np.max(np.abs(integers.astype(np.int32))))
    if peak_integer < 100 or peak_integer >= 32767:
        raise ValueError(f"{label}: 無音に近い、またはクリップしている")
    samples = integers.astype(np.float64) / 32768
    return samples, rate, {
        "seconds": frames / rate, "sampleRate": rate, "channels": channels,
        "sha256": digest(data), "samplePeakDbfs": db(peak_integer / 32768),
    }


def resample(samples: np.ndarray, source_rate: int) -> np.ndarray:
    """64タップの窓付きsinc。尺・音程を変えず44.1kHzへ変換する。"""
    if source_rate == RATE:
        return samples.copy()
    count = round(len(samples) * RATE / source_rate)
    output = np.zeros((count, samples.shape[1]), dtype=np.float64)
    offsets = np.arange(-31, 33)
    cutoff = min(1.0, RATE / source_rate) * 0.95
    for start in range(0, count, 8192):
        end = min(count, start + 8192)
        position = np.arange(start, end) * source_rate / RATE
        indexes = np.floor(position).astype(np.int64)[:, None] + offsets
        distance = position[:, None] - indexes
        weights = np.sinc(distance * cutoff) * cutoff
        weights *= np.cos(np.pi * distance / 64) ** 2
        weights[np.abs(distance) >= 32] = 0
        weights /= np.sum(weights, axis=1, keepdims=True)
        valid = (indexes >= 0) & (indexes < len(samples))
        indexes = np.clip(indexes, 0, len(samples) - 1)
        output[start:end] = np.sum(samples[indexes] * (weights * valid)[:, :, None], axis=1)
    return output


def prepare_voice(samples: np.ndarray, rate: int) -> tuple[np.ndarray, float]:
    voice = resample(samples, rate)
    if voice.shape[1] == 1:
        voice = np.repeat(voice, 2, axis=1)
    # 無音の長さで声の音量が変わらないよう、活動区間のRMSを基準にする。
    power = np.mean(voice * voice, axis=1)
    active = power > max(float(np.max(power)) * 0.01, 10 ** (-55 / 10))
    if np.count_nonzero(active) < RATE * 0.05:
        raise ValueError("有効な声が50ms未満")
    active_rms = float(np.sqrt(np.mean(power[active])))
    gain = min(10 ** (-20 / 20) / active_rms, 10 ** (-6 / 20) / float(np.max(np.abs(voice))))
    voice *= gain
    edge = min(round(RATE * 0.005), len(voice) // 2)
    ramp = np.sin(np.linspace(0, np.pi / 2, edge)) ** 2
    voice[:edge] *= ramp[:, None]
    voice[-edge:] *= ramp[::-1, None]
    return voice, gain


def encode(samples: np.ndarray) -> bytes:
    output = io.BytesIO()
    with wave.open(output, "wb") as target:
        target.setnchannels(2)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(np.round(np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
    return output.getvalue()


def build(audio_dir: Path, script_path: Path) -> tuple[bytes, dict, dict[str, bytes]]:
    script_data = script_path.read_bytes()
    spec = json.loads(script_data)
    clips = spec["clips"]
    ids = [clip["id"] for clip in clips]
    if len(ids) != 10 or set(ids) != set(OPENING_IDS + GUIDE_IDS):
        raise ValueError("OP5本と初回案内5本、重複のない全10本の台本が必要")
    indexed = {clip["id"]: clip for clip in clips}
    for index, item in enumerate(OPENING_IDS):
        clip = indexed[item]
        if not math.isclose(clip["start"], 0.7 + index * 8, abs_tol=1e-8):
            raise ValueError(f"{item}: 開始位置は0.7 + 8×章番号にする")
        if clip["maxSeconds"] != 6.6:
            raise ValueError(f"{item}: 最大6.6秒の枠を維持する")

    # 未生成ならここで失敗し、カタログも音楽も一切書き換えない。
    for item in ids:
        if not (audio_dir / "luna" / f"{item}.wav").is_file():
            raise ValueError(f"未生成の音声: {item}")
    provenance = json.loads((audio_dir / "luna/provenance.json").read_bytes())
    expected = {"provider": "Gemini", "model": spec["model"], "voice": spec["voice"],
                "scriptSha256": digest(script_data)}
    if any(provenance.get(key) != value for key, value in expected.items()):
        raise ValueError("音声の由来と現在の台本/モデル/声が一致しない。明示的に再生成する")
    if provenance.get("complete") is not True:
        raise ValueError("音声生成が全10本完了していない")

    sources = {}
    metadata = {}
    files = {}
    voice_assets = {}
    for item in ids:
        data = (audio_dir / "luna" / f"{item}.wav").read_bytes()
        samples, rate, info = pcm(data, item, indexed[item]["maxSeconds"])
        if provenance.get("clips", {}).get(item, {}).get("sha256") != info["sha256"]:
            raise ValueError(f"{item}: 生成時からファイルが変わっている")
        sources[item] = (samples, rate)
        metadata[item] = info
        relative = f"luna/{item}.{info['sha256']}.wav"
        files[relative] = data
        voice_assets[item] = "audio/" + relative

    music_data = (audio_dir / "opening_music.wav").read_bytes()
    music, rate, music_info = pcm(music_data, "opening_music", 40)
    if rate != RATE or music.shape != (FRAMES, 2):
        raise ValueError("BGMは40秒/44.1kHz/stereoが必要")
    duck = np.ones(FRAMES, dtype=np.float64)
    narration = np.zeros_like(music)
    time = np.arange(FRAMES) / RATE
    gains = {}
    for item in OPENING_IDS:
        voice, gain = prepare_voice(*sources[item])
        start = indexed[item]["start"]
        offset = round(start * RATE)
        end = offset + len(voice)
        if end > FRAMES:
            raise ValueError(f"{item}: OPからはみ出す")
        narration[offset:end] += voice
        # 声の直前180msで下げ、終了後450msで戻す。発声の小休止では揺らさない。
        down = np.clip((time - (start - 0.18)) / 0.18, 0, 1)
        up = np.clip(((end / RATE + 0.45) - time) / 0.45, 0, 1)
        activity = (down * down * (3 - 2 * down)) * (up * up * (3 - 2 * up))
        duck = np.minimum(duck, 1 - activity * (1 - 10 ** (-6 / 20)))
        gains[item] = round(gain, 6)
    mixed = music * (0.8 * duck[:, None]) + narration
    sample_peak = float(np.max(np.abs(mixed)))
    # 万一の重なりは全体を下げ、リミッターで語尾を潰さない。
    master_gain = min(1.0, 10 ** (-2 / 20) / sample_peak)
    mixed *= master_gain
    data = encode(mixed)
    decoded, _, mix_info = pcm(data, "opening_mix", 40)
    if decoded.shape != (FRAMES, 2) or np.any(decoded[-round(RATE * 0.05) :]):
        raise ValueError("ミックスの長さまたは末尾に異常")
    oversampled = max(float(np.max(np.abs(
        np.fft.irfft(np.fft.rfft(decoded[:, channel]), FRAMES * 4) * 4
    ))) for channel in range(2))
    if oversampled >= 10 ** (-1 / 20):
        raise ValueError("補間ピークの余裕が不足。声の音量を下げて再確認する")
    relative_mix = f"opening_mix.{digest(data)}.wav"
    files[relative_mix] = data
    old_catalog = json.loads((audio_dir / "catalog.json").read_bytes())
    if not isinstance(old_catalog, dict):
        raise ValueError("現在のcatalog.jsonが不正")
    catalog = {
        **old_catalog, "openingAsset": "audio/" + relative_mix,
        "voices": voice_assets, "voiceProvider": "Gemini", "voiceStatus": "ready",
        "voiceModel": spec["model"], "voiceName": spec["voice"],
        "scriptSha256": digest(script_data), "voiceMetadata": metadata,
        "openingMix": {**mix_info, "musicSha256": music_info["sha256"],
                       "fourfoldPeakDbfs": db(oversampled), "musicGain": 0.8,
                       "duckDb": -6, "voiceGains": gains, "masterGain": master_gain},
    }
    return data, catalog, files


def atomic_write(path: Path, data: bytes, immutable: bool = False) -> None:
    if immutable and path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"不変ファイルの内容が異なる: {path.name}")
        return
    temporary = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".mix-", suffix=".tmp", delete=False) as target:
            temporary = Path(target.name)
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def publish(audio_dir: Path, catalog: dict, files: dict[str, bytes]) -> None:
    # 既存catalogが参照する音声は更新しない。途中失敗でも旧世代は再生可能。
    for relative, data in files.items():
        atomic_write(audio_dir / relative, data, immutable=True)
    catalog_data = (json.dumps(catalog, ensure_ascii=False, indent=2) + "\n").encode()
    atomic_write(audio_dir / "catalog.json", catalog_data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio-dir", type=Path, default=ROOT / "assets/audio")
    parser.add_argument("--script", type=Path, default=ROOT / "tools/audio/luna_script.json")
    parser.add_argument("--check-only", action="store_true", help="合成と検査だけ行い、公開しない")
    parser.add_argument("--preview", type=Path, help="確認用WAVを別の場所へ書き出す（例: /private/tmp/opening_mix.wav）")
    args = parser.parse_args()
    try:
        data, catalog, files = build(args.audio_dir, args.script)
        if args.preview:
            # previewを既存catalogやBGMへ誤指定して上書きすることを防ぐ。
            if args.preview.resolve().is_relative_to(args.audio_dir.resolve()):
                raise ValueError("previewは配布audioディレクトリ外へ指定する")
            atomic_write(args.preview, data)
        if not args.check_only:
            publish(args.audio_dir, catalog, files)
        print(json.dumps({"published": not args.check_only,
                          "openingAsset": catalog["openingAsset"],
                          "voiceCount": len(catalog["voices"]),
                          "mix": catalog["openingMix"]}, ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"音声の公開を中止しました: {error}") from None


if __name__ == "__main__":
    main()
