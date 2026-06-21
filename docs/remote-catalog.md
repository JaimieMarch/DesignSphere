# Remote Model Catalog

DesignSphere's furniture/décor catalog is **hosted, not bundled**: 180+ models
live in a Cloudflare R2 bucket and stream into the app on demand. This document
covers the end-to-end system — how assets are produced, how they're hosted, and
how the app loads them.

```
 source meshes (glb / .blend)
        │  Tools/catalog-pipeline/build_catalog.py
        ▼
 catalog/  ── models/<id>.usdz
        ├── thumbnails/<id>.png
        └── catalog.json                 ← the manifest
        │  rclone copy
        ▼
 Cloudflare R2 (public bucket)
        │  HTTPS
        ▼
 app: RemoteCatalogService → ModelFileStore → RealityKit
```

## 1. Asset pipeline (`Tools/catalog-pipeline/`)

`build_catalog.py` turns a folder of source models into an upload-ready tree.
For each model it:

1. **Converts to usdz** — glb/obj via the system Apple USD tools
   (`usdcat` + `usdzip`); textured Poly Haven `.blend` via headless Blender
   (`export_usdz.py`), which transcodes `.exr` maps to png, drops the world
   environment, and downscales textures. Output passes `usdchecker --arkit`.
2. **Renders a thumbnail** with `usdrecord` (transparent background, auto-framed).
3. **Infers a category** (`seating`, `tables`, `lighting`, …) and **placement
   metadata** (surface classification, plane alignment, stacking, real-world
   scale) from the model name.
4. **Records** byte size + SHA-256 for integrity/cache invalidation, and a
   `textured` flag (false for geometry-only models).

It emits `models/`, `thumbnails/`, and `catalog.json`, which are uploaded with
`rclone copy … r2:designsphere-catalog`. See the
[pipeline README](../Tools/catalog-pipeline/README.md) for the full workflow.

## 2. The manifest (`catalog.json`)

```json
{
  "version": 1,
  "generatedAt": "…",
  "models": [
    {
      "id": "modern_arm_chair_01",
      "displayName": "Modern Arm Chair 01",
      "category": "seating",
      "textured": true,
      "file": { "url": "models/modern_arm_chair_01.usdz", "bytes": 12000000, "sha256": "…" },
      "thumbnail": { "url": "thumbnails/modern_arm_chair_01.png" },
      "placement": {
        "classification": "floor", "plane": "horizontal",
        "canStack": true, "needsPhysics": false, "preserveRealWorldScale": true
      }
    }
  ]
}
```

The manifest is the contract between the pipeline and the app; its Swift mirror
is `CatalogManifest`. `placement` is the per-model metadata that the app would
otherwise hard-code in `ModelType`, so the app can load models it has never seen.

## 3. In-app loader (`Sources/.../RemoteCatalog/`)

| Type | Responsibility |
|---|---|
| `RemoteCatalogService` (`@MainActor`) | Fetches `catalog.json` (network-first, cached to Application Support for offline), maps entries to `ModelType`s with placement + remote URLs, exposes per-id categories. |
| `ModelFileStore` (`actor`) | Resolves a remote `ModelType` to a local usdz: cache-first, else download → SHA-256 verify → store under `Caches/RemoteModels/`. Coalesces concurrent requests; LRU-evicts past a ~1.5 GB budget. |
| `RemoteDownloadProgress` (`@MainActor`) | Per-model 0–1 download progress + failure state, observed by the catalog UI for the progress overlay and retry affordance. |

**Flow:** at launch `CollaborativeSessionController.loadRemoteCatalog()` populates
`modelManager.modelTypes` from the manifest (no eager downloads). The catalog UI
lists every model with its hosted thumbnail. Tapping a model calls
`addModel` → `Model.loadModelEntity`, which routes remote models through
`ModelFileStore` (download + cache) before handing the usdz to RealityKit.
Untextured models (`textured: false`) get a neutral grey material at load.

`AppFeatureFlags.remoteCatalogEnabled` / `remoteCatalogBaseURL` gate and point
the loader; with the flag off the app falls back to any bundled models.

## 4. Resilience

- **Offline:** the manifest is disk-cached, and previously downloaded models load
  from the on-device cache; the catalog opens without a network round-trip.
- **Integrity:** every download is SHA-256-verified against the manifest.
- **Failure UX:** a failed download surfaces a retry button on the catalog cell;
  a failed manifest fetch shows a "Catalog unavailable" + retry state.

## Updating the catalog

1. Add/adjust source assets, then re-run `build_catalog.py`.
2. `rclone copy` the changed files (usdz/thumbnails) and `catalog.json` to R2.
3. Clients pick up changes on next launch; changed models re-download because
   their SHA-256 (and cache key) changed.
