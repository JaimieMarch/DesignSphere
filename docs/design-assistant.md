# Design Assistant

DesignSphere's assistant gives catalog-driven design help that is **free,
on-device, private, and offline** — no API key, no backend, no per-use cost. It
stays entirely inside Apple's ecosystem.

```
 catalog (ModelDescriptors: category + finish)
        │
        ▼
 DesignAdvisor  ── roomSet(for:)        → furnish a room
        │       ├─ complements(...)      → complete the space
        │       ├─ similar(to:)          → more like this
        │       └─ models(inCategories:) → from named categories
        ▼
 AIAssistantView (toolbar ✨) ── suggestion cards, tap-to-place, "Place all"
        ▲
        │  (optional, device-only)
 DesignAssistantLLM ── Foundation Models → structured intent → DesignAdvisor
```

## Components

| Type | Where | Role |
|---|---|---|
| `DesignAdvisor` | package | Deterministic recommendations: room templates + a category-affinity graph. Decoupled behind `DesignCatalogItem` (category key + finish flag) so it's UI-agnostic and unit-tested. |
| `PaletteAdvisor` | package | Curated interior-design color palettes (UI-agnostic RGB), surfaced in the editor's Style tab for finishing untextured "Customizable" models. |
| `AIAssistantView` | app | The UI: "Furnish a room" (Living/Bedroom/Office/Dining), "Complete my space", suggestion cards (real thumbnails) that place on tap, and "Place all" (arranged). |
| `DesignAssistantLLM` | app | Optional natural-language layer over `DesignAdvisor`, via Apple **Foundation Models**. |
| `CollaborativeSessionController.placeArrangedModels` | package | Lays a set on the floor in front of the viewer instead of stacking it. |

## How the recommendations work

- **Furnish a room** — each `RoomType` defines ordered category *slots*
  (Living Room = sofa, coffee table, TV, lamp, rug, accent chair). `roomSet`
  fills each slot from the catalog, preferring textured models, never repeating;
  slots with no matching models are skipped.
- **Complete my space** — `complements` reads the categories already placed and
  ranks complementary categories via an affinity graph, favouring ones not yet
  present, then picks specific models.
- **Place all** — arranges the unplaced suggestions in centered rows on the
  floor in front of the viewer (head-tracked frame on device; fixed in-front
  fallback in the simulator).

## The on-device LLM layer (Foundation Models)

When the device supports Apple Intelligence (visionOS 26), the assistant shows a
natural-language box. `DesignAssistantLLM` runs a `LanguageModelSession` with a
`@Generable` response type to map free text ("a cozy minimalist reading nook")
to a room and/or categories, which feed `DesignAdvisor`. It is gated by
`canImport(FoundationModels)` **and** a `SystemLanguageModel` availability check,
so it **degrades to the quick-action buttons** when unavailable — including in
the simulator, where Apple Intelligence does not run.

This keeps the feature **$0 and key-free**: the LLM is the OS's on-device model,
nothing leaves the device, and there is no cloud dependency.

## Why not a cloud LLM or CreateML?

- **Cloud LLM (Claude/OpenAI/…):** costs per request, needs a backend or an
  embedded key (insecure), and sends data off device. Avoided.
- **CreateML:** needs labeled training data the project doesn't have; for a
  ~180-item catalog, curated rules + the on-device LLM beat a trained model. The
  realistic future use is **re-ranking** recommendations from logged
  query→placement behaviour, once that data exists.

## Tested

`DesignAdvisor` and `PaletteAdvisor` are covered by the package XCTest suite
(room composition, complements, category picks, palette integrity). The LLM path
is device-only to exercise; the rest is fully testable in the simulator.
