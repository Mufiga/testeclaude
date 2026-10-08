#!/usr/bin/env python3
"""Roda a geometria do RockKit fora do Roblox e renderiza uma previa.

Junta os stubs + os modulos de src/shared/RockKit + main.luau num unico arquivo,
executa com o interpretador `luau`, valida a saida e desenha as malhas num PNG.

Uso:
    python3 tools/preview/run.py [--out build/preview.png]

Precisa de `luau` no PATH (ou LUAU_BIN apontando para o binario) e de Pillow.
"""

from __future__ import annotations

import argparse
import math
import os
import pathlib
import re
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "src" / "shared" / "RockKit"
HERE = pathlib.Path(__file__).resolve().parent

REQUIRE = re.compile(r"require\(\s*script(?:\.Parent)?\.([A-Za-z_][A-Za-z0-9_]*)\s*\)")
EXPORT_TYPE = re.compile(r"^export type ", re.MULTILINE)

PREAMBLE = """
local __modules: { [string]: () -> any } = {}
local __loaded: { [string]: any } = {}
local function __require(name: string): any
\tlocal cached = __loaded[name]
\tif cached ~= nil then return cached end
\tlocal factory = __modules[name]
\tif not factory then error("modulo ausente: " .. name, 2) end
\tlocal result = factory()
\t__loaded[name] = result
\treturn result
end
"""

# Apenas os modulos de geometria pura: os outros dependem de Instance/DataModel.
GEOMETRY_MODULES = ("Noise", "Shape", "Presets")

ROCK_COLOR = (150, 112, 99)
BACKGROUND = (30, 31, 35)
GROUND = (44, 40, 40)
KEY_LIGHT = (-0.45, 0.78, 0.44)
FILL_LIGHT = (0.6, 0.25, -0.5)


def build_script(destination: pathlib.Path) -> None:
    parts = [(HERE / "stubs.luau").read_text(), PREAMBLE]
    for name in GEOMETRY_MODULES:
        body = (SOURCE / f"{name}.luau").read_text()
        body = REQUIRE.sub(lambda m: f'__require("{m.group(1)}")', body)
        body = EXPORT_TYPE.sub("type ", body)
        indented = "\n".join(("\t" + l) if l.strip() else l for l in body.splitlines())
        parts.append(f'\n__modules["{name}"] = function()\n{indented}\nend\n')
    parts.append((HERE / "main.luau").read_text())
    destination.write_text("--!nocheck\n--!nolint\n" + "".join(parts))


def run_luau(script: pathlib.Path) -> str:
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        sys.exit("luau nao encontrado: instale-o ou aponte LUAU_BIN para o binario")
    done = subprocess.run([binary, str(script)], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"luau falhou:\n{done.stdout}\n{done.stderr}")
    return done.stdout


def parse_output(text: str):
    meshes: list[tuple[str, list, list]] = []
    info: list[str] = []
    result = None
    name = None
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    failures: list[str] = []

    for line in text.splitlines():
        if line.startswith("#OBJ "):
            name, verts, faces = line[5:].strip(), [], []
        elif line.startswith("#ENDOBJ"):
            meshes.append((name, verts, faces))
            name = None
        elif line.startswith("#INFO "):
            info.append(line[6:].strip())
        elif line.startswith("#RESULT"):
            result = line[8:].strip()
        elif line.startswith("FALHA:"):
            failures.append(line)
        elif name is not None:
            if line.startswith("v "):
                x, y, z = line[2:].split()
                verts.append((float(x), float(y), float(z)))
            elif line.startswith("f "):
                a, b, c = line[2:].split()
                faces.append((int(a) - 1, int(b) - 1, int(c) - 1))

    return meshes, info, result, failures


def normalize(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v) if length else (0.0, 0.0, 0.0)


def render_mesh(draw: ImageDraw.ImageDraw, mesh, box: tuple[int, int, int, int]) -> None:
    """Rasteriza a malha por pintor (fundo primeiro) com sombreamento flat."""
    _, verts, faces = mesh
    left, top, width, height = box

    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    center = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
    radius = max(
        max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)) / 2,
        1e-3,
    )

    # camera orbitando um pouco acima do horizonte
    eye_dir = normalize((0.62, 0.24, 1.0))
    distance = radius * 3.4
    eye = tuple(center[i] + eye_dir[i] * distance for i in range(3))

    forward = normalize(tuple(center[i] - eye[i] for i in range(3)))
    right = normalize(
        (
            forward[1] * 0.0 - forward[2] * 1.0,
            forward[2] * 0.0 - forward[0] * 0.0,
            forward[0] * 1.0 - forward[1] * 0.0,
        )
    )
    up = (
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    )
    up = normalize(up)

    focal = min(width, height) * 1.45

    def project(p):
        rel = tuple(p[i] - eye[i] for i in range(3))
        depth = sum(rel[i] * forward[i] for i in range(3))
        if depth <= 1e-4:
            return None
        sx = sum(rel[i] * right[i] for i in range(3))
        sy = sum(rel[i] * up[i] for i in range(3))
        return (left + width / 2 + sx * focal / depth, top + height / 2 - sy * focal / depth, depth)

    key = normalize(KEY_LIGHT)
    fill = normalize(FILL_LIGHT)

    drawable = []
    for a, b, c in faces:
        pa, pb, pc = verts[a], verts[b], verts[c]
        u = tuple(pb[i] - pa[i] for i in range(3))
        w = tuple(pc[i] - pa[i] for i in range(3))
        normal = normalize(
            (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        )
        to_eye = normalize(tuple(eye[i] - pa[i] for i in range(3)))
        if sum(normal[i] * to_eye[i] for i in range(3)) <= 0:
            continue  # backface

        screen = [project(p) for p in (pa, pb, pc)]
        if any(s is None for s in screen):
            continue

        lambert = max(0.0, sum(normal[i] * key[i] for i in range(3)))
        bounce = max(0.0, sum(normal[i] * fill[i] for i in range(3)))
        shade = 0.26 + 0.74 * lambert + 0.16 * bounce
        color = tuple(min(255, int(channel * shade)) for channel in ROCK_COLOR)

        depth = sum(s[2] for s in screen) / 3
        drawable.append((depth, [(s[0], s[1]) for s in screen], color))

    drawable.sort(key=lambda item: -item[0])
    for _, polygon, color in drawable:
        draw.polygon(polygon, fill=color)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "build" / "preview.png"))
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--cell", type=int, default=300)
    args = parser.parse_args()

    scratch = ROOT / "build" / "_preview_bundle.luau"
    scratch.parent.mkdir(parents=True, exist_ok=True)
    build_script(scratch)

    meshes, info, result, failures = parse_output(run_luau(scratch))

    for line in info:
        print("  " + line)
    for line in failures:
        print("  " + line)
    print(f"  validacao: {result}")

    columns = args.columns
    rows = math.ceil(len(meshes) / columns)
    cell = args.cell
    image = Image.new("RGB", (columns * cell, rows * cell), BACKGROUND)
    draw = ImageDraw.Draw(image)

    for index, mesh in enumerate(meshes):
        cx = (index % columns) * cell
        cy = (index // columns) * cell
        draw.rectangle([cx, cy + cell - 26, cx + cell, cy + cell], fill=GROUND)
        render_mesh(draw, mesh, (cx, cy + 16, cell, cell - 60))
        height = max(v[1] for v in mesh[1]) - min(v[1] for v in mesh[1])
        draw.text((cx + 10, cy + 10), f"{mesh[0]}  ({height:.1f} studs)", fill=(226, 226, 230))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(f"  previa: {out.relative_to(ROOT)}")

    return 0 if result == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
