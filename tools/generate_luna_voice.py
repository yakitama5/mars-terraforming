#!/usr/bin/env python3
"""Generate bundled Luna narration. The API key never enters game assets.

Use GEMINI_API_KEY, or --key-file /absolute/private/path. Requires Python 3
stdlib only. An explicit call performs billed provider requests when applicable.
An existing validated clip is reused; --force regenerates it. Publication is a
separate action. Docs: https://ai.google.dev/gemini-api/docs/generate-content/speech-generation
"""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import urllib.error
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/audio/luna_script.json'
DEST = ROOT / 'assets/audio/luna'


def inspect_wav(data, limit):
    with wave.open(io.BytesIO(data), 'rb') as wav:
        if (wav.getcomptype() != 'NONE' or wav.getsampwidth() != 2
                or wav.getnchannels() not in (1, 2)):
            raise ValueError('Expected PCM16 mono/stereo WAV')
        rate = wav.getframerate()
        if not 8000 <= rate <= 96000:
            raise ValueError('Unsupported PCM sample rate')
        frames = wav.getnframes()
        duration = frames / rate
        if not .25 < duration <= limit:
            raise ValueError(f'Clip duration {duration:.3f}s exceeds slot {limit}s; shorten/re-record the line')
        raw = wav.readframes(frames)
        if len(raw) != frames * wav.getnchannels() * 2:
            raise ValueError('Truncated PCM data; no existing asset was changed')
        samples = struct.unpack('<' + 'h' * (len(raw) // 2), raw)
        peak = max(abs(v) for v in samples)
        if peak < 100 or peak >= 32767:
            raise ValueError('Clip is silent or clipped; re-record before bundling')
    return {'seconds': round(duration, 4), 'sampleRate': rate,
            'sha256': hashlib.sha256(data).hexdigest()}


def generate(key, spec, clip):
    payload = {
        'contents': [{'role': 'user', 'parts': [{
            'text': clip['text'],
            'speech_metadata': {'style': spec['style'] +
                                f' Complete this line naturally within {clip["maxSeconds"]} seconds.'}
        }]}],
        'generationConfig': {'responseModalities': ['AUDIO'],
                             'speechConfig': {'voiceConfig': {'voice': spec['voice']}}}
    }
    request = urllib.request.Request(
        f'https://generativelanguage.googleapis.com/v1beta/models/{spec["model"]}:generateContent',
        data=json.dumps(payload).encode(), method='POST',
        headers={'Content-Type': 'application/json', 'x-goog-api-key': key})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        # Provider bodies/headers can contain request details; do not log them.
        raise RuntimeError(f'Gemini returned HTTP {error.code}; check key, model access and quota') from None
    candidates = result.get('candidates') or [{}]
    parts = candidates[0].get('content', {}).get('parts', [])
    audio = next((p['inlineData'] for p in parts if 'inlineData' in p), None)
    if not audio:
        raise RuntimeError('Gemini returned no audio; no existing asset was changed')
    data = base64.b64decode(audio['data'], validate=True)
    if data[:4] != b'RIFF':
        # Older compatible providers can return raw 24 kHz PCM16 instead.
        mime = audio.get('mimeType', '')
        if not mime.lower().startswith('audio/l16') or 'rate=24000' not in mime:
            raise ValueError('Unsupported audio encoding; expected WAV or PCM16/24000')
        if not data or len(data) % 2:
            raise ValueError('Incomplete raw PCM16 data')
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(24000)
            wav.writeframes(data)
        data = buffer.getvalue()
    return data


def atomic_write(path, data):
    """一時ファイルを同じディレクトリへ確定してから置き換える。"""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.' + path.name,
                                         suffix='.tmp', delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', type=Path)
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    if args.force and args.validate_only:
        parser.error('--force and --validate-only cannot be combined')
    script_data = SCRIPT.read_bytes()
    spec = json.loads(script_data)
    ids = [clip['id'] for clip in spec['clips']]
    if len(set(ids)) != len(ids) or any(not re.fullmatch(r'[A-Za-z0-9_]+', item) for item in ids):
        parser.error('Invalid or duplicate clip ID')
    identity = {'provider': 'Gemini', 'model': spec['model'], 'voice': spec['voice'],
                'scriptSha256': hashlib.sha256(script_data).hexdigest()}
    provenance_path = DEST / 'provenance.json'
    previous = {}
    if provenance_path.exists():
        try:
            previous = json.loads(provenance_path.read_text())
        except (ValueError, OSError):
            if not args.force:
                parser.error('Unreadable provenance; use --force to regenerate')
    if not isinstance(previous, dict):
        if not args.force:
            parser.error('Invalid provenance; use --force to regenerate')
        previous = {}
    has_existing = any((DEST / f'{item}.wav').exists() for item in ids)
    matching = all(previous.get(key) == value for key, value in identity.items())
    if has_existing and not matching and not args.force:
        parser.error('Script/model/voice or provenance changed; use --force to regenerate')
    cached = previous.get('clips', {}) if matching and not args.force else {}
    if not isinstance(cached, dict):
        parser.error('Invalid clip provenance; use --force to regenerate')
    metadata = {}
    pending = []
    # 全キャッシュを先に検査する。古い声へ新しい台本の由来を付け直さない。
    for clip in spec['clips']:
        path = DEST / f'{clip["id"]}.wav'
        recorded = cached.get(clip['id'])
        if path.exists() and isinstance(recorded, dict):
            data = path.read_bytes()
            if recorded.get('sha256') != hashlib.sha256(data).hexdigest():
                parser.error(f'{clip["id"]}: cached file changed; use --force to regenerate')
            metadata[clip['id']] = inspect_wav(data, clip['maxSeconds'])
        elif args.validate_only:
            raise SystemExit(f'Missing verified narration: {clip["id"]}')
        else:
            pending.append(clip)
    if pending:
        key = (args.key_file.read_text().strip() if args.key_file else
               os.environ.get('GEMINI_API_KEY', '').strip())
        if not key:
            parser.error('Set GEMINI_API_KEY or provide --key-file. Never put a key into repository files.')
        DEST.mkdir(parents=True, exist_ok=True)
        for clip in pending:
            data = generate(key, spec, clip)
            metadata[clip['id']] = inspect_wav(data, clip['maxSeconds'])
            atomic_write(DEST / f'{clip["id"]}.wav', data)
            # 中断後はここまでの検証済み音声だけを再利用できる。
            atomic_write(provenance_path, (json.dumps({
                **identity, 'complete': len(metadata) == len(ids), 'clips': metadata
            }, ensure_ascii=False, indent=2) + '\n').encode())
    for clip in spec['clips']:
        print(f'{clip["id"]}: {metadata[clip["id"]]["seconds"]:.3f}s verified')
    if not args.validate_only:
        atomic_write(provenance_path, (json.dumps({
            **identity, 'complete': True, 'clips': metadata
        }, ensure_ascii=False, indent=2) + '\n').encode())
        print('All clips validated. Run tools/mix_opening_audio.py to publish the bundled audio catalog.')


if __name__ == '__main__':
    main()
