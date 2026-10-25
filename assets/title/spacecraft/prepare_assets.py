"""NASAの原GLBを検証し、PBR材質だけを調整してタイトル素材を再生成する。

実行例: PillowとNumPyのあるPythonでこのファイルを実行する。
原素材はキャッシュへ保存し、アプリには派生GLBだけを採用する。
"""

from hashlib import sha256
from io import BytesIO
from pathlib import Path
import json
import struct
import tempfile
from urllib.parse import quote
from urllib.request import urlopen

import numpy as np
from PIL import Image, ImageFilter


REVISION = "11ebb4ee043715aefbba6aeec8a61746fad67fa7"
SOURCES = {
    "nasa_mro.glb": (
        "3D Models/Mars Reconnaissance Orbiter (MRO) (A)/"
        "Mars Reconnaissance Orbiter (MRO) (A).glb",
        "b195c566d227dec8e42ca2fafcc2a8cc26a127e04ed577e4b9515199d2002d9e",
    ),
    "nasa_saturn_v.glb": (
        "3D Models/Saturn V/Saturn V.glb",
        "6c44497bce54ee0b09d0edb8e33a6f484762a320dab1c54b383e434f5bba06b5",
    ),
    "nasa_bennu.glb": (
        "3D Models/1999 RQ36 asteroid/1999 RQ36 asteroid.glb",
        "644af15678447df90c2d9e85674809c7fc70f439e0865418aa6618a8483b7958",
    ),
}
DESTINATION = Path(__file__).resolve().parent
BENNU_MOSAIC_URL = (
    "https://www.nasa.gov/wp-content/uploads/2023/03/"
    "bennu_global_mosaic_reduced_size.png"
)
BENNU_MOSAIC_HASH = "cc2d73cf23ca87a998db8171f67a56aec09ff94e5acbe1630108471236eeb197"


def read_source(name, source_path, expected_hash):
    cache = Path(tempfile.gettempdir()) / "dear-mars-nasa-source" / name
    cache.parent.mkdir(parents=True, exist_ok=True)
    if cache.exists():
        data = cache.read_bytes()
    else:
        url = (
            "https://raw.githubusercontent.com/nasa/NASA-3D-Resources/"
            + REVISION + "/" + quote(source_path)
        )
        with urlopen(url, timeout=90) as response:
            data = response.read()
        cache.write_bytes(data)
    if sha256(data).hexdigest() != expected_hash:
        raise ValueError(f"原素材のSHA-256が一致しません: {name}")
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError("glTF 2.0のGLBではありません")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:
        raise ValueError("GLBのJSONチャンクがありません")
    document = json.loads(data[20:20 + json_length])
    binary_length, binary_type = struct.unpack_from("<II", data, 20 + json_length)
    if binary_type != 0x004E4942:
        raise ValueError("GLBのBINチャンクがありません")
    binary_start = 28 + json_length
    binary = bytearray(data[binary_start:binary_start + binary_length])
    return document, binary


def add_foil_normal(document, binary):
    # 原アトラスの箔のしわだけを、微細な凹凸の補助へ使う。
    # 太陽電池・塗装・光学機器には適用しない。
    original_image = next(
        image for image in document["images"]
        if image["mimeType"] == "image/jpeg"
    )
    view = document["bufferViews"][original_image["bufferView"]]
    start = view.get("byteOffset", 0)
    image = Image.open(BytesIO(binary[start:start + view["byteLength"]]))
    image = image.convert("L").resize((1024, 1024), Image.Resampling.LANCZOS)
    image = image.filter(ImageFilter.GaussianBlur(.55))
    height = np.asarray(image, dtype=np.float32) / 255
    dy, dx = np.gradient(height)
    x, y = -dx * 5.5, dy * 5.5
    z = np.ones_like(x)
    length = np.sqrt(x * x + y * y + z * z)
    normal = np.stack((x / length, y / length, z / length), axis=2)
    pixels = np.round((normal * .5 + .5) * 255).clip(0, 255).astype(np.uint8)
    stream = BytesIO()
    Image.fromarray(pixels).save(stream, format="PNG", optimize=True)
    encoded = stream.getvalue()
    while len(binary) % 4:
        binary.append(0)
    document["bufferViews"].append({
        "buffer": 0,
        "byteOffset": len(binary),
        "byteLength": len(encoded),
    })
    image_index = len(document["images"])
    document["images"].append({
        "name": "Dear Mars foil micro-normal from NASA MRO atlas",
        "bufferView": len(document["bufferViews"]) - 1,
        "mimeType": "image/png",
    })
    binary.extend(encoded)
    texture_index = len(document["textures"])
    document["textures"].append({"source": image_index})
    return texture_index


def tune_mro(document, binary):
    normal = add_foil_normal(document, binary)
    settings = {
        "default #2": (.16, .6),
        "foil": (.76, .4),
        "lens": (.18, .19),
        "parts": (.58, .43),
        "rocket": (.71, .37),
        "pole": (.72, .36),
        "solar_L": (.14, .31),
        "solar_edge": (.65, .4),
        "solar_R": (.14, .31),
        "tower": (.55, .44),
        "cover": (.3, .5),
    }
    for material in document["materials"]:
        name = material.get("name")
        metallic, roughness = settings[name]
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = metallic
        pbr["roughnessFactor"] = roughness
        if name == "foil":
            material["normalTexture"] = {"index": normal, "scale": .3}


def tune_saturn(document, binary):
    metals = {
        "blinn6SG": (.62, .38),
        "blinn5SG": (.58, .4),
        "blinn3SG": (.72, .37),
        "blinn4SG": (.5, .42),
        "initialShadingGr": (.52, .45),
    }
    for material in document["materials"]:
        name = material.get("name")
        metallic, roughness = metals.get(name, (.03, .54))
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = metallic
        pbr["roughnessFactor"] = roughness


def tune_bennu(document, binary):
    cache = Path(tempfile.gettempdir()) / "dear-mars-nasa-source" / "bennu-mosaic.png"
    if not cache.exists():
        with urlopen(BENNU_MOSAIC_URL, timeout=30) as response:
            cache.write_bytes(response.read())
    mosaic = cache.read_bytes()
    if sha256(mosaic).hexdigest() != BENNU_MOSAIC_HASH:
        raise ValueError("Bennu全球画像のSHA-256が一致しません")

    def accessor_values(index, width, dtype):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return np.frombuffer(
            binary, dtype=dtype, count=accessor["count"] * width, offset=start
        ).copy().reshape((-1, width))

    primitive = document["meshes"][0]["primitives"][0]
    positions = accessor_values(primitive["attributes"]["POSITION"], 3, "<f4")
    normals = accessor_values(primitive["attributes"]["NORMAL"], 3, "<f4")
    faces = accessor_values(primitive["indices"], 1, "<u2").reshape((-1, 3))
    radii = np.linalg.norm(positions, axis=1)
    u = (np.arctan2(positions[:, 2], positions[:, 0]) + np.pi) / (2 * np.pi)
    v = .5 - np.arcsin(np.clip(positions[:, 1] / radii, -1, 1)) / np.pi
    uv = np.stack((u, v), axis=1).tolist()
    points, directions = positions.tolist(), normals.tolist()
    duplicates = {}
    # 経度の継目ではUVだけを複製し、表面の頂点座標と三角形を保持する。
    for face in faces:
        if np.ptp(u[face]) <= .5:
            continue
        for corner, index in enumerate(face):
            index = int(index)
            if u[index] >= .5:
                continue
            if index not in duplicates:
                duplicates[index] = len(points)
                points.append(points[index])
                directions.append(directions[index])
                uv.append([float(u[index]) + 1, float(v[index])])
            face[corner] = duplicates[index]

    def add_view(data, target=None):
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        document["bufferViews"].append(view)
        binary.extend(data)
        return len(document["bufferViews"]) - 1

    def add_attribute(values, kind):
        values = np.asarray(values, dtype="<f4")
        view = add_view(values.tobytes(), 34962)
        document["accessors"].append({
            "bufferView": view, "componentType": 5126,
            "count": len(values), "type": kind,
            "min": values.min(axis=0).tolist(), "max": values.max(axis=0).tolist(),
        })
        return len(document["accessors"]) - 1

    primitive["attributes"] = {
        "POSITION": add_attribute(points, "VEC3"),
        "NORMAL": add_attribute(directions, "VEC3"),
        "TEXCOORD_0": add_attribute(uv, "VEC2"),
    }
    indices = faces.astype("<u2").reshape(-1)
    index_view = add_view(indices.tobytes(), 34963)
    document["accessors"].append({
        "bufferView": index_view, "componentType": 5123,
        "count": len(indices), "type": "SCALAR",
    })
    primitive["indices"] = len(document["accessors"]) - 1
    document["images"], document["textures"] = [], []

    def add_image(data, name):
        view = add_view(data)
        index = len(document["images"])
        document["images"].append({
            "bufferView": view, "mimeType": "image/png", "name": name,
        })
        document["textures"].append({"source": index})
        return len(document["textures"]) - 1

    albedo_index = add_image(mosaic, "NASA Goddard University of Arizona Bennu mosaic")
    image = Image.open(BytesIO(mosaic)).convert("L")
    image = image.filter(ImageFilter.GaussianBlur(.5))
    intensity = np.asarray(image, dtype=np.float32) / 255
    dy, dx = np.gradient(intensity)
    x, y, z = -dx * 3, dy * 3, np.ones_like(dx)
    length = np.sqrt(x * x + y * y + z * z)
    normal = np.stack((x / length, y / length, z / length), axis=2)
    pixels = np.round((normal * .5 + .5) * 255).clip(0, 255).astype(np.uint8)
    stream = BytesIO()
    Image.fromarray(pixels).save(stream, format="PNG", optimize=True)
    normal_index = add_image(stream.getvalue(), "Bennu title-only surface micro-normal")
    document["materials"][0] = {
        "name": "Bennu carbon-rich regolith",
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": albedo_index},
            "baseColorFactor": [.58, .58, .58, 1],
            "metallicFactor": 0,
            "roughnessFactor": .96,
        },
        "normalTexture": {"index": normal_index, "scale": .18},
    }


def encode(document, binary, *, source_filename):
    document["buffers"][0]["byteLength"] = len(binary)
    document["asset"]["extras"] = {
        "source": "NASA-3D-Resources",
        "sourceRevision": REVISION,
        "changes": (
            "Dear Mars: original vertex positions and normals retained; "
            "seam vertices duplicated and spherical UV added; NASA measured "
            "Bennu mosaic and derived title-only normal added; PBR adjusted"
            if source_filename == "nasa_bennu.glb"
            else "Dear Mars PBR tuning; original geometry and albedo retained"
        ),
    }
    source = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
    source += b" " * ((-len(source)) % 4)
    binary += b"\0" * ((-len(binary)) % 4)
    length = 12 + 8 + len(source) + 8 + len(binary)
    return (
        struct.pack("<III", 0x46546C67, 2, length)
        + struct.pack("<II", len(source), 0x4E4F534A) + source
        + struct.pack("<II", len(binary), 0x004E4942) + binary
    )


manifest = {"sourceRevision": REVISION, "assets": []}
for filename, (source_path, expected_hash) in SOURCES.items():
    model, binary = read_source(filename, source_path, expected_hash)
    if filename == "nasa_mro.glb":
        tune_mro(model, binary)
    elif filename == "nasa_bennu.glb":
        tune_bennu(model, binary)
    else:
        tune_saturn(model, binary)
    result = encode(model, binary, source_filename=filename)
    (DESTINATION / filename).write_bytes(result)
    digest = sha256(result).hexdigest()
    manifest["assets"].append({
        "file": filename,
        "sourcePath": source_path,
        "sourceSha256": expected_hash,
        "sha256": digest,
        "bytes": len(result),
        "meshes": len(model["meshes"]),
        "materials": len(model["materials"]),
        "triangles": sum(
            model["accessors"][primitive["indices"]]["count"] // 3
            for mesh in model["meshes"] for primitive in mesh["primitives"]
        ),
    })
    if filename == "nasa_bennu.glb":
        manifest["assets"][-1].update({
            "textureSource": BENNU_MOSAIC_URL,
            "textureSourceSha256": BENNU_MOSAIC_HASH,
        })
    print(filename, len(result), digest)
(DESTINATION / "asset-manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
)
