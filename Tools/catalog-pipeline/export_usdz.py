"""Blender-side exporter: a single .blend -> textured .usdz.

Run headless by build_catalog.py as:
    blender --background <model>.blend --python export_usdz.py -- <out>.usdz

usdz/RealityKit only support png/jpg textures, but the Poly Haven .blend files
reference some maps as .exr. We transcode those to png *next to the source*
(so Blender's usdz packager resolves the relative ./textures path) and repoint
the image datablocks before export, then delete the derived pngs afterward so
the source folders are left clean. Export is Y-up / -Z-forward (ARKit-oriented),
and textures are downscaled (USDZ_DOWNSCALE, default 1024) to keep the on-demand
download size reasonable.
"""

import bpy
import os
import sys

DOWNSCALE = os.environ.get("USDZ_DOWNSCALE", "1024")
DOWNSCALE_PX = int(DOWNSCALE) if DOWNSCALE.isdigit() else 1024


def convert_exr_textures():
    """Transcode each .exr-backed image to png in place. Returns the list of
    png paths we created (so the caller can remove them after export).

    Headless Blender lazy-loads images, so reloading the existing datablock
    yields "no image data". We load the .exr fresh and call scale(), which both
    forces the pixel read and downscales in one step, save it as png next to the
    source, then repoint the material's image datablock at that png so the
    exporter packages it. The created pngs are deleted after export."""
    created = []
    for img in list(bpy.data.images):
        raw = img.filepath_raw or ""
        if not raw.lower().endswith(".exr"):
            continue
        abs_exr = bpy.path.abspath(raw)
        new_png = os.path.splitext(abs_exr)[0] + ".png"
        pre_existing = os.path.exists(new_png)
        try:
            fresh = bpy.data.images.load(abs_exr)
            fresh.scale(DOWNSCALE_PX, DOWNSCALE_PX)  # forces load + downscale
            fresh.file_format = "PNG"
            fresh.filepath_raw = new_png
            fresh.save()
            bpy.data.images.remove(fresh)
            img.filepath = new_png
            img.filepath_raw = new_png
            img.reload()
            if not pre_existing:
                created.append(new_png)
        except Exception as exc:  # noqa: BLE001 - keep going, log the bad map
            print(f"  EXR->PNG failed for {raw}: {exc}")
    print(f"  converted {len(created)} exr texture(s)")
    return created


def main():
    out = sys.argv[sys.argv.index("--") + 1:][0]
    os.makedirs(os.path.dirname(out), exist_ok=True)

    created = convert_exr_textures()
    try:
        bpy.ops.wm.usd_export(
            filepath=out,
            export_materials=True,
            export_textures=True,
            overwrite_textures=True,
            relative_paths=True,
            export_normals=True,
            # Don't export the world/environment: it pulls an .hdr into the usdz
            # (ARKit rejects hdr) and we only want the furniture itself.
            convert_world_material=False,
            convert_orientation=True,
            export_global_up_selection="Y",
            export_global_forward_selection="NEGATIVE_Z",
            evaluation_mode="RENDER",
            usdz_downscale_size=DOWNSCALE,
        )
        print(f"  exported {out}")
    finally:
        for path in created:
            try:
                os.remove(path)
            except OSError:
                pass


if __name__ == "__main__":
    main()
