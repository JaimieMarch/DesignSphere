# Catalog pipeline

Builds the DesignSphere **remote model catalog** from a folder of source assets
(per-model folders containing `.glb` / `.obj` / `.fbx`) and produces a tree ready
to upload to Cloudflare R2:

```
_catalog_build/
  models/<id>.usdz
  thumbnails/<id>.png
  catalog.json          # the manifest the app fetches at launch
```

The assets themselves are **never committed** — only this script and (optionally)
the generated `catalog.json`. Build output is gitignored.

## One-time setup

1. **usdzconvert** (glb/obj/fbx → usdz) — Apple's USDPython tools:
   download from <https://developer.apple.com/augmented-reality/tools/>, unzip,
   then either add its `USD/` scripts dir to `PATH` or point the pipeline at it:
   ```sh
   export USDZCONVERT=/path/to/USD/usdzconvert
   ```
   `qlmanage` (thumbnails) ships with macOS — nothing to install.

2. **rclone** (upload to R2):
   ```sh
   brew install rclone
   rclone config        # new remote, type "s3", provider "Cloudflare",
                        # endpoint https://<accountid>.r2.cloudflarestorage.com
   ```

## Usage

```sh
# 1. Review categorization without converting (no usdzconvert needed):
python3 build_catalog.py --source ~/Downloads --dry-run

# 2. Full build:
python3 build_catalog.py --source ~/Downloads
#   --limit 5   process a handful first
#   --force     re-convert models whose usdz already exists

# 3. Upload to R2 (bucket public-read):
rclone copy ~/Downloads/_catalog_build r2:designsphere-catalog --progress
```

## Manifest shape (`catalog.json`)

```json
{
  "version": 1,
  "generatedAt": "2026-06-19T00:00:00+00:00",
  "models": [
    {
      "id": "wooden_chair_01",
      "displayName": "Wooden Chair 01",
      "category": "seating",
      "file": { "url": "models/wooden_chair_01.usdz", "bytes": 123456, "sha256": "…" },
      "thumbnail": { "url": "thumbnails/wooden_chair_01.png" },
      "placement": {
        "classification": "floor", "plane": "horizontal",
        "canStack": true, "needsPhysics": false, "preserveRealWorldScale": true
      }
    }
  ]
}
```

`placement` is the per-model metadata currently hard-coded in `ModelType.swift`;
moving it into the manifest lets the app load remote models it has never seen.
`sha256` lets the on-device cache detect when a re-uploaded model has changed.

## Notes

- Categories are inferred from model names (`CATEGORY_RULES` in the script) and
  match `ModelCategory.rawValue`, so they also drive the in-app semantic search.
  Review the `--dry-run` output and tweak the rules before a full build.
- `preserveRealWorldScale` defaults to `true` because the Poly Haven source set
  is modelled at real-world scale.
