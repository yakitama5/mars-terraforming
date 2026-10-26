#!/usr/bin/env python3
"""Rebuild the adopted NASA VTAD Jupiter, Saturn and ring images.

Development-only image conversion; no Flutter runtime dependencies are added.
Requires NumPy and Pillow (verified with 2.3.5 / 12.3.0). Originals and outputs
are checked against fixed SHA-256 values. See docs/title-gas-giant-assets.md.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import urllib.request

import numpy as np
from PIL import Image

SOURCE: Path
OUTPUT: Path

ORIGINALS = {
    'nasa-jupiter': (
        'https://assets.science.nasa.gov/content/dam/science/psd/solar/2023/09/j/Jupiter_1_142984.glb',
        '8edc4e9b88b73ca1b125a258f0ecaef7fc6494a7cadda37704af459a119f4870',
    ),
    'nasa-saturn': (
        'https://assets.science.nasa.gov/content/dam/science/psd/solar/2023/09/s/Saturn_1_120536.glb',
        '8dbfde533b13e938408d8aded1d1ce48a084806233f67775371d83013dba7d38',
    ),
}
OUTPUT_SHA256 = {
    'jupiter_vtad_2k.jpg': '991ceeb3367f42c2cb34b5f2eb20a5a125ac39e8a9d47f303e2efe8b7af0af30',
    'saturn_vtad_2k.jpg': '84d76932e3852d2998bc743512c799e4cb7cc4349c1080fa67b001282300beec',
    'saturn_rings_vtad_2k.png': '9f4dab45476b8c00279ec49822f68c76214ea97b6ecef15030e61cd0604723c5',
}


def prepare_sources(no_download):
    SOURCE.mkdir(parents=True, exist_ok=True)
    for stem, (url, expected) in ORIGINALS.items():
        path = SOURCE / (stem + '.glb')
        if path.exists():
            raw = path.read_bytes()
        else:
            if no_download:
                raise ValueError(f'Missing original: {path}')
            with urllib.request.urlopen(url, timeout=60) as response:
                raw = response.read()
        actual = hashlib.sha256(raw).hexdigest()
        if actual != expected:
            raise ValueError(f'Original SHA-256 mismatch: {stem}: {actual}')
        if not path.exists():
            path.write_bytes(raw)
        if raw[:4] != b'glTF' or struct.unpack_from('<I', raw, 4)[0] != 2:
            raise ValueError(f'Invalid GLB header: {stem}')
        length = struct.unpack_from('<I', raw, 12)[0]
        model = json.loads(raw[20:20 + length])
        binary = raw[28 + length:]
        image_directory = SOURCE / stem
        image_directory.mkdir(exist_ok=True)
        for index, image in enumerate(model['images']):
            if image['mimeType'] != 'image/png':
                raise ValueError(f'Unexpected image format: {stem}/{index}')
            view = model['bufferViews'][image['bufferView']]
            begin = view.get('byteOffset', 0)
            payload = binary[begin:begin + view['byteLength']]
            image_path = image_directory / f'{index}.png'
            if image_path.exists() and image_path.read_bytes() != payload:
                raise ValueError(f'Existing extracted source differs: {image_path}')
            if not image_path.exists():
                image_path.write_bytes(payload)

def glb_arrays(stem):
    raw = (SOURCE / (stem + '.glb')).read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + length])
    binary = raw[28 + length:]
    def accessor(index):
        a = document['accessors'][index]
        view = document['bufferViews'][a['bufferView']]
        dtype = {5126: '<f4', 5123: '<u2', 5125: '<u4'}[a['componentType']]
        channels = {'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
        return np.frombuffer(binary, dtype=dtype, count=a['count'] * channels,
            offset=view.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, channels)
    primitive = document['meshes'][0]['primitives'][0]
    return (accessor(primitive['attributes']['POSITION']),
        accessor(primitive['attributes']['TEXCOORD_0']), accessor(primitive['indices']).reshape(-1, 3))

def bilinear(image, x, y):
    x = np.clip(x, 0, image.shape[1] - 1)
    y = np.clip(y, 0, image.shape[0] - 1)
    a, b = np.floor(x).astype(int), np.floor(y).astype(int)
    c, d = np.minimum(a + 1, image.shape[1] - 1), np.minimum(b + 1, image.shape[0] - 1)
    tx, ty = (x - a)[..., None], (y - b)[..., None]
    return ((image[b, a] * (1 - tx) + image[b, c] * tx) * (1 - ty) +
        (image[d, a] * (1 - tx) + image[d, c] * tx) * ty)

def reproject(stem, filename):
    positions, uv, triangles = glb_arrays(stem)
    axes = np.max(np.abs(positions), axis=0)
    sphere = positions / axes
    atlas = np.asarray(Image.open(SOURCE / stem / '0.png').convert('RGB')).astype(np.float32)
    groups = {}
    for tri in triangles:
        center = sphere[tri].mean(axis=0)
        axis = int(np.argmax(np.abs(center)))
        groups.setdefault((axis, int(np.sign(center[axis]))), []).append(tri)
    width, height, resolution = 2048, 1024, 1024
    longitude = (np.arange(width) + .5) / width * (2 * np.pi) - np.pi
    latitude = np.pi / 2 - (np.arange(height) + .5) / height * np.pi
    lon, lat = np.meshgrid(longitude, latitude)
    directions = np.stack([np.cos(lat) * np.sin(lon), np.sin(lat), -np.cos(lat) * np.cos(lon)], axis=-1)
    major = np.argmax(np.abs(directions), axis=-1)
    result = np.empty((height, width, 3), dtype=np.float32)
    for (axis, sign), faces in groups.items():
        other = [i for i in range(3) if i != axis]
        cube = sphere[:, other] / np.maximum(np.abs(sphere[:, axis, None]), 1e-9)
        lookup = np.full((resolution, resolution, 2), np.nan, dtype=np.float32)
        for tri in faces:
            xy = (cube[tri] + 1) * (resolution - 1) / 2
            minimum = np.maximum(np.floor(xy.min(axis=0)).astype(int), 0)
            maximum = np.minimum(np.ceil(xy.max(axis=0)).astype(int), resolution - 1)
            x, y = np.meshgrid(np.arange(minimum[0], maximum[0] + 1), np.arange(minimum[1], maximum[1] + 1))
            a, b, c = xy
            determinant = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(determinant) < 1e-12:
                continue
            w0 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / determinant
            w1 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / determinant
            w2 = 1 - w0 - w1
            mask = np.minimum(np.minimum(w0, w1), w2) >= -1e-5
            mapped = w0[..., None] * uv[tri[0]] + w1[..., None] * uv[tri[1]] + w2[..., None] * uv[tri[2]]
            lookup[y[mask], x[mask]] = mapped[mask]
        missing = ~np.isfinite(lookup[..., 0])
        print(stem, axis, sign, 'edge pixels unfilled', int(missing.sum()), flush=True)
        # Float32 GLB vertices can miss the exact cube boundary by <1 pixel.
        # Extend only that boundary, never interpolate across an atlas face.
        if missing[2:-2, 2:-2].any():
            raise ValueError(f'{stem}: interior hole in cube face {axis}/{sign}')
        lookup[:2] = lookup[2]
        lookup[-2:] = lookup[-3]
        lookup[:, :2] = lookup[:, 2:3]
        lookup[:, -2:] = lookup[:, -3:-2]
        if not np.isfinite(lookup).all():
            raise ValueError(f'{stem}: invalid cube edge {axis}/{sign}')
        mask = (major == axis) & (np.sign(directions[..., axis]) == sign)
        q = directions[mask]
        coordinates = q[:, other] / np.abs(q[:, axis, None])
        mapped = bilinear(lookup, (coordinates[:, 0] + 1) * (resolution - 1) / 2,
            (coordinates[:, 1] + 1) * (resolution - 1) / 2)
        colors = bilinear(atlas, mapped[:, 0] * (atlas.shape[1] - 1), mapped[:, 1] * (atlas.shape[0] - 1))
        result[mask] = colors
    Image.fromarray(np.rint(np.clip(result, 0, 255)).astype(np.uint8)).save(
        OUTPUT / filename, quality=95, subsampling=0, optimize=True)
    return {'file': filename, 'source_axes': axes.tolist(), 'output': [width, height]}


def main():
    global SOURCE, OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path,
        default=Path(tempfile.gettempdir()) / 'dear-mars-gas-giant-sources',
        help='Cache of SHA-verified NASA GLB originals and extracted PNGs')
    parser.add_argument('--output-dir', type=Path,
        default=Path(__file__).resolve().parents[1] / 'assets/title/giants')
    parser.add_argument('--no-download', action='store_true',
        help='Require the originals to be cached; do not make network requests')
    args = parser.parse_args()
    SOURCE = args.source_dir.resolve()
    destination = args.output_dir.resolve()
    prepare_sources(args.no_download)
    # Verify all generated bytes before touching any checked-in output. A
    # different JPEG/PNG encoder must not silently replace the adopted assets.
    with tempfile.TemporaryDirectory(prefix='dear-mars-giant-conversion-') as staged:
        OUTPUT = Path(staged)
        results = [reproject('nasa-jupiter', 'jupiter_vtad_2k.jpg'),
            reproject('nasa-saturn', 'saturn_vtad_2k.jpg')]
        ring = Image.open(SOURCE / 'nasa-saturn/1.png').convert('RGBA')
        ring.resize((2048, 128), Image.Resampling.LANCZOS).save(
            OUTPUT / 'saturn_rings_vtad_2k.png', optimize=True)
        payloads = {}
        for filename, expected in OUTPUT_SHA256.items():
            data = (OUTPUT / filename).read_bytes()
            actual = hashlib.sha256(data).hexdigest()
            if actual != expected:
                raise ValueError(f'Output SHA-256 mismatch: {filename}: {actual}. '
                    'The adopted encoder environment is NumPy 2.3.5 / Pillow 12.3.0; '
                    'existing outputs have not been changed.')
            payloads[filename] = data
        destination.mkdir(parents=True, exist_ok=True)
        for filename, data in payloads.items():
            (destination / filename).write_bytes(data)
            print(json.dumps({'file': filename, 'bytes': len(data),
                'sha256': hashlib.sha256(data).hexdigest()}))
        print(json.dumps(results))


if __name__ == '__main__':
    main()
