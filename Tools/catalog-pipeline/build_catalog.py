#!/usr/bin/env python3
"""Build the DesignSphere remote model catalog from a folder of source assets.

For each model folder under --source (a directory containing `<name>.glb`, or
falling back to `.obj` / `.fbx`), this:

  1. converts the mesh to USDZ via Apple's `usdzconvert` (USDPython),
  2. renders a thumbnail PNG with `qlmanage` (macOS QuickLook),
  3. assigns a catalog category and placement metadata from the model's name,
  4. records a sha256 + byte size for cache invalidation,

then emits a ready-to-upload tree:

    <out>/
      models/<id>.usdz
      thumbnails/<id>.png
      catalog.json

`catalog.json` is the manifest the app fetches from R2: it carries everything
the app needs (display name, category, file/thumbnail paths, integrity hashes,
and the placement metadata that is currently hard-coded in ModelType.swift).

Use --dry-run to scan + categorize without converting (no usdzconvert needed),
which is the fast way to review the category mapping before a full build.

Examples
--------
    # Review what would be built and how each model is categorized:
    python3 build_catalog.py --source ~/Downloads --dry-run

    # Full build into ~/Downloads/_catalog_build:
    python3 build_catalog.py --source ~/Downloads

Then upload (see README): rclone copy <out> r2:designsphere-catalog
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path

# Manifest schema version. Bump when the JSON shape changes so older app builds
# can refuse a manifest they don't understand.
MANIFEST_VERSION = 1

# Source mesh formats in order of preference. glb is self-contained (geometry +
# materials + embedded textures) so it converts to USDZ with the best fidelity.
# `.blend` is last: only folders that ship _only_ a .blend (the textured Poly
# Haven set) fall through to the Blender exporter.
SOURCE_EXTENSIONS = (".glb", ".gltf", ".obj", ".fbx", ".blend")

# Category keywords, checked in this order; first hit wins. Keys are
# ModelCategory.rawValue values used by the app and the search engine.
CATEGORY_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("seating", ("chair", "stool", "sofa", "couch", "bench", "seat", "armchair",
                 "ottoman", "settee", "throne", "pew", "recliner")),
    ("beds", ("bed", "mattress", "crib", "bunk", "cradle")),
    ("tables", ("table", "desk", "nightstand", "sidetable", "console", "workbench")),
    ("storage", ("rack", "shelf", "shelving", "bookcase", "bookshelf", "cabinet",
                 "closet", "wardrobe", "dresser", "drawer", "cupboard", "sideboard",
                 "locker", "crate", "basket", "bin", "chest", "trunk")),
    ("lighting", ("lamp", "light", "chandelier", "lantern", "sconce", "candle",
                  "torch", "pendant")),
    ("media", ("tv", "television", "monitor", "screen", "radio", "speaker", "console_game")),
    ("decor", ("panelling", "panel", "clock", "mirror", "painting", "frame", "picture",
               "vase", "plant", "pot", "planter", "trophy", "fountain", "statue",
               "sculpture", "ornament", "rug", "curtain", "gate", "fence", "boot",
               "towel", "toilet_roll", "holder", "rail", "sign", "flag", "book",
               "bottle", "bowl", "plate", "cup", "jug", "bucket", "ladder")),
]

# Anything not matched by a specific category falls back to decor (the catalog
# keeps every prop rather than dropping it), so the placement hints below carry
# most of the nuance for that long tail.

# Wall / ceiling / table hints override the category's default floor placement.
WALL_HINTS = ("panel", "panelling", "clock", "mirror", "painting", "frame",
              "picture", "tv", "television", "monitor", "sign", "flag",
              "door", "deer", "antler", "vent")
CEILING_HINTS = ("chandelier", "pendant", "ceiling")
TABLETOP_HINTS = ("vase", "bottle", "bowl", "plate", "cup", "jug", "trophy",
                  "candle", "lamp", "clock_small", "ornament", "book",
                  "mug", "goblet", "glass", "cocktail", "amphora", "canned",
                  "food", "pottery", "keyboard", "mouse")


@dataclass
class Placement:
    classification: str  # floor | wall | ceiling | table | any
    plane: str           # horizontal | vertical | any
    canStack: bool
    needsPhysics: bool
    # Poly Haven assets are modelled at real-world scale, so the app should not
    # renormalize them. Defaults to True for this source set.
    preserveRealWorldScale: bool


def categorize(name: str) -> str:
    lowered = name.lower()
    for category, keywords in CATEGORY_RULES:
        if any(k in lowered for k in keywords):
            return category
    # Unmatched props (instruments, tableware, doors, footwear, …) are kept as
    # decor rather than dropped, so the catalog never silently loses an asset.
    return "decor"


def placement_for(name: str, category: str) -> Placement:
    lowered = name.lower()
    stackable = category in ("seating", "tables", "storage")

    if any(h in lowered for h in CEILING_HINTS):
        return Placement("ceiling", "horizontal", False, False, True)
    if any(h in lowered for h in WALL_HINTS):
        return Placement("wall", "vertical", False, False, True)
    if category == "decor" and any(h in lowered for h in TABLETOP_HINTS):
        return Placement("table", "horizontal", False, False, True)
    if category == "lighting":  # lamps and the like sit on a surface
        return Placement("table", "horizontal", False, False, True)
    if category == "unknown":   # conservative: prefer the floor
        return Placement("floor", "horizontal", False, False, True)
    return Placement("floor", "horizontal", stackable, False, True)


def model_id_from_folder(name: str) -> str:
    """Folder name -> catalog id, dropping a trailing resolution suffix so
    `modern_arm_chair_01_4k` becomes `modern_arm_chair_01`."""
    return re.sub(r"_\d+k$", "", name.lower())


def display_name(model_id: str) -> str:
    return " ".join(part.capitalize() for part in model_id.replace("-", "_").split("_"))


def find_source_mesh(folder: Path) -> Path | None:
    """Pick the best source mesh in a model folder, preferring `<folder>.glb`."""
    for ext in SOURCE_EXTENSIONS:
        named = folder / f"{folder.name}{ext}"
        if named.exists():
            return named
    for ext in SOURCE_EXTENSIONS:  # fall back to any mesh of that type
        matches = sorted(folder.glob(f"*{ext}"))
        if matches:
            return matches[0]
    return None


def discover_models(source: Path, textured_only: bool = False) -> list[tuple[str, Path]]:
    """Return (id, source_mesh) for every model folder under `source`.
    With `textured_only`, keep only folders whose source is a .blend (the
    textured Poly Haven set), skipping the untextured glb/obj/fbx folders."""
    by_id: dict[str, Path] = {}
    for child in sorted(p for p in source.iterdir() if p.is_dir()):
        if child.name.startswith(".") or child.name.startswith("_"):
            continue
        if child.name == "DesignSphere":  # the stray repo clone in Downloads
            continue
        mesh = find_source_mesh(child)
        if mesh is None:
            continue
        if textured_only and mesh.suffix.lower() != ".blend":
            continue
        model_id = model_id_from_folder(child.name)
        # On an id collision (e.g. dining_chair_02 vs dining_chair_02_4k), keep
        # the textured .blend source so the textured model always wins.
        existing = by_id.get(model_id)
        if existing is None or (mesh.suffix.lower() == ".blend" and existing.suffix.lower() != ".blend"):
            by_id[model_id] = mesh
    return sorted(by_id.items())


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def convert_to_usdz(args: argparse.Namespace, mesh: Path, out_usdz: Path) -> None:
    out_usdz.parent.mkdir(parents=True, exist_ok=True)

    if mesh.suffix.lower() == ".blend":
        # Blender headless: opens the .blend (materials/textures intact),
        # transcodes any .exr maps, and exports a downscaled, ARKit-oriented usdz.
        script = Path(__file__).resolve().parent / "export_usdz.py"
        env = dict(os.environ, USDZ_DOWNSCALE=str(args.downscale))
        out_usdz.unlink(missing_ok=True)
        subprocess.run([args.blender, "--background", str(mesh),
                        "--python", str(script), "--", str(out_usdz)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
        if not out_usdz.exists():
            raise subprocess.CalledProcessError(1, "blender")
        return

    converter = args.converter
    if converter == "native":
        # Use the system Apple USD tools (no usdzconvert install needed): the
        # glTF file-format plugin lets usdcat read .glb/.obj, then usdzip wraps
        # the crate layer into a usdz archive. usdcat may print plugin warnings
        # and a nonzero status even on success, so we verify by output instead.
        tmp_usdc = out_usdz.with_suffix(".usdc")
        tmp_usdc.unlink(missing_ok=True)
        subprocess.run(["usdcat", str(mesh), "-o", str(tmp_usdc)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if not tmp_usdc.exists() or tmp_usdc.stat().st_size == 0:
            raise subprocess.CalledProcessError(1, "usdcat")
        out_usdz.unlink(missing_ok=True)
        subprocess.run(["usdzip", str(out_usdz), str(tmp_usdc)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tmp_usdc.unlink(missing_ok=True)
        if not out_usdz.exists():
            raise subprocess.CalledProcessError(1, "usdzip")
        return

    subprocess.run([converter, str(mesh), str(out_usdz)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def render_thumbnail(usdz: Path, out_png: Path, size: int = 512, timeout: int = 90) -> bool:
    """Render a transparent-background thumbnail with Apple's `usdrecord` (Hydra
    GPU renderer): it auto-frames the model, shows materials, and writes the png
    directly. Returns False on failure/timeout."""
    out_png.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["usdrecord", "--imageWidth", str(size), "--complexity", "high", str(usdz), str(out_png)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False
    return out_png.exists()


def build(args: argparse.Namespace) -> int:
    source = Path(args.source).expanduser().resolve()
    out = Path(args.out).expanduser().resolve()
    if not source.is_dir():
        print(f"error: source is not a directory: {source}", file=sys.stderr)
        return 2

    models = discover_models(source, textured_only=args.textured_only)
    if args.limit:
        models = models[: args.limit]
    if not models:
        print(f"No model folders found under {source}", file=sys.stderr)
        return 1

    print(f"Discovered {len(models)} model(s) under {source}")
    if not args.dry_run:
        (out / "models").mkdir(parents=True, exist_ok=True)
        (out / "thumbnails").mkdir(parents=True, exist_ok=True)

    entries: list[dict] = []
    category_counts: dict[str, int] = {}
    failures: list[str] = []

    for model_id, mesh in models:
        category = categorize(model_id)
        placement = placement_for(model_id, category)
        category_counts[category] = category_counts.get(category, 0) + 1

        if args.dry_run:
            print(f"  {model_id:<32} {category:<9} {mesh.suffix:<5} -> "
                  f"{placement.classification}/{placement.plane}")
            continue

        usdz_path = out / "models" / f"{model_id}.usdz"
        thumb_path = out / "thumbnails" / f"{model_id}.png"
        try:
            if args.force or not usdz_path.exists():
                convert_to_usdz(args, mesh, usdz_path)
        except subprocess.CalledProcessError:
            print(f"  ✗ convert failed: {model_id}", file=sys.stderr)
            failures.append(model_id)
            continue
        except FileNotFoundError:
            print(f"error: converter '{args.converter}' not found on PATH.\n"
                  f"Install Apple USDPython (see README) or pass --converter.",
                  file=sys.stderr)
            return 2

        has_thumb = False if args.skip_thumbnails else render_thumbnail(usdz_path, thumb_path)

        entry = {
            "id": model_id,
            "displayName": display_name(model_id),
            "category": category,
            "file": {
                "url": f"models/{model_id}.usdz",
                "bytes": usdz_path.stat().st_size,
                "sha256": sha256_of(usdz_path),
            },
            "placement": asdict(placement),
        }
        if has_thumb:
            entry["thumbnail"] = {"url": f"thumbnails/{model_id}.png"}
        entries.append(entry)
        print(f"  ✓ {model_id:<32} {category}")

    if not args.dry_run:
        manifest = {
            "version": MANIFEST_VERSION,
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "models": entries,
        }
        (out / "catalog.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"\nWrote {len(entries)} models to {out / 'catalog.json'}")
        if failures:
            print(f"{len(failures)} conversion failure(s): {', '.join(failures)}")

    print("\nCategory distribution:")
    for category, count in sorted(category_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {category:<9} {count}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", default="~/Downloads",
                        help="Folder containing per-model subfolders (default: ~/Downloads)")
    parser.add_argument("--out", default="~/Downloads/_catalog_build",
                        help="Output tree for usdz/thumbnails/catalog.json")
    parser.add_argument("--converter", default=os.environ.get("USDZCONVERT", "native"),
                        help="'native' = system usdcat+usdzip (default); or a usdzconvert path")
    parser.add_argument("--dry-run", action="store_true",
                        help="Scan and categorize only; no conversion (no usdzconvert needed)")
    parser.add_argument("--force", action="store_true",
                        help="Re-convert models whose usdz already exists")
    parser.add_argument("--skip-thumbnails", action="store_true",
                        help="Skip QuickLook thumbnail rendering (it can be slow/hang on usdz)")
    parser.add_argument("--blender",
                        default=os.path.expanduser("~/Applications/Blender.app/Contents/MacOS/Blender"),
                        help="Blender executable, used to convert .blend sources")
    parser.add_argument("--downscale", default="1024",
                        help="Max texture dimension for .blend conversion (default 1024)")
    parser.add_argument("--textured-only", action="store_true",
                        help="Only process folders whose source is a .blend (the textured set)")
    parser.add_argument("--limit", type=int, default=0,
                        help="Process at most N models (for quick test runs)")
    return build(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
