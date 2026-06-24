# Design Sphere App

**See Your Vision. From Within.**

DesignSphere is an interior design app built from the ground up for the Apple Vision Pro that allows users to design or customize their space in real time, in real space. The app reimagines interior design through spatial computing, turning any room into a blank canvas where furniture and décor appear true to scale and true to life.

The app eliminates the struggle of visualizing furniture fit, costly big commitments, painful returns, and the physical effort of moving items around. Instead of being limited by traditional screens, DesignSphere uses intuitive gesture-based controls to let users interact with high-fidelity 3D models that respond naturally to their environment. Objects snap into place respecting room geometry, with built-in spatial recognition understanding room size and surfaces to position items correctly.

Designed for students, interior designers, real estate stagers, and businesses alike, DesignSphere adapts to suit different needs. Whether you're a student furnishing your first apartment, a designer presenting concepts to clients, or a business owner planning a retail layout, DesignSphere provides the tools to plan, visualize, and test interior layouts efficiently—making spatial computing practical and accessible for everyday design.

## Features

### Core Functionality

- **Intuitive Interface**: Clean, floating translucent menus that adhere to Apple's design language, with gesture-based controls that stay out of the way while remaining easily accessible
- **Remote Model Catalog**: A cloud-hosted catalog of 180+ furniture and décor models (Cloudflare R2) that the app browses instantly and downloads on demand — with hosted thumbnails, a per-model download progress indicator, on-device caching with LRU eviction, and offline fallback to the last-loaded catalog
- **Intent-Aware Search**: Catalog search that understands the *idea* behind a query — searching "sofa" surfaces every seating item, "lighting" finds lamps and chandeliers — via a curated category/synonym vocabulary (see `ModelSearchEngine`)
- **Design Assistant**: An on-device assistant that furnishes a room in one tap (Living Room / Bedroom / Office / Dining), completes a space by suggesting the pieces it's missing, and arranges a whole set in front of you — all free, offline, and catalog-driven (see `DesignAdvisor`). On Apple-Intelligence hardware it also accepts natural-language requests via Apple's on-device **Foundation Models** (no API key, no cost)
- **Designer Palettes**: Curated interior-design color palettes (`PaletteAdvisor`) in the editor for quickly finishing the untextured "Customizable" models
- **Advanced Model Editing**: Comprehensive editing tools allowing users to adjust size, position, rotation, style, texture, and color of each item
- **Spatial Recognition**: Built-in spatial APIs anchor objects with incredible accuracy, matching scale and perspective to your room's exact dimensions
- **Project Management**: Save and organize multiple room layouts, create different versions to compare design options, and return to previous projects anytime
- **Location-Aware Loading**: The app can recognize a space and automatically load the related design when you return

### Additional Features (UI Implemented, Functionality In Development)

- **Model Import**: Import custom USDZ files from your device to expand the furniture library
- **Focus Modes**: Interface for toggling real-world item visibility and accessing neutral design spaces
- **Measurement Tools**: Object dimensions, distance between objects, and a virtual ruler (manager + UI complete; spatial overlays verified on device)
- **SharePlay Collaboration**: Multi-user session interface with session codes for real-time collaboration (UI present; peer-to-peer networking in development)

### Planned Features

- **LiDAR Scanning**: Built-in scanner to capture real furniture with LiDAR and convert them into reusable 3D models
- **CloudKit Integration**: Cloud-based project syncing enabling users to save layouts across devices and locations, improving app performance while reducing storage footprint
- **Full AI Integration**: Complete AI-powered design suggestions and automated layout assistance implementation
- **Voice Commands**: Full voice control implementation for hands-free operation
- **Advanced SharePlay**: Complete peer-to-peer collaboration with synchronized model manipulation

## Use Cases

### Personal Use

- **Students & Young Adults**: Furnish apartments and dorm rooms without costly mistakes
- **Homeowners & Renters**: Visualize furniture arrangements before purchasing or moving heavy items
- **DIY Decorators**: Experiment with different layouts, styles, and color schemes risk-free
- **Moving & Relocating**: Plan furniture placement in a new space before the moving truck arrives

### Professional Applications

- **Interior Designers**: Create immersive client presentations and explore multiple design concepts quickly
- **Real Estate Staging**: Virtually stage properties to help potential buyers visualize possibilities
- **Commercial Planning**: Design retail layouts, restaurant seating, salon stations, and office spaces
- **Renovation Projects**: Preview and plan space changes before committing to physical alterations

## Technical Architecture

- **RealityKit** for high-fidelity 3D rendering and spatial interactions
- **ARKit** for world tracking and spatial mapping
- **SwiftUI** for the user interface with native visionOS design patterns
- **World Anchors** for persistent spatial tracking, allowing projects to be anchored to real-world locations
- **JSON-based project serialization** for lightweight, human-readable project files
- **Remote catalog over Cloudflare R2**: a JSON manifest (`catalog.json`) plus per-model `usdz` and thumbnails are served from object storage; the app fetches the manifest at launch and downloads models lazily on placement (`RemoteCatalogService`, `ModelFileStore`), verifying each download's SHA-256 and caching under `Caches/` with an LRU budget
- **Swift Package (`XRShareCollaboration`)** holds the reusable engine: catalog, search, measurement, manipulation, and model management — covered by an XCTest suite

The remote-catalog system (asset pipeline → R2 → in-app loader) is documented in [docs/remote-catalog.md](docs/remote-catalog.md); the on-device Design Assistant (recommendations + optional Foundation Models layer) in [docs/design-assistant.md](docs/design-assistant.md).

## Model Catalog

The catalog is **hosted, not bundled**: 180+ furniture and décor models live in a
Cloudflare R2 bucket and stream into the app on demand. Browsing is instant
(thumbnails + metadata only); a model's `usdz` downloads the first time you place
it, then is cached on device.

Assets are produced by the catalog pipeline in
[Tools/catalog-pipeline/](Tools/catalog-pipeline/), which converts source meshes
to ARKit-compatible `usdz` (native `usdcat`/`usdzip` for glb, headless Blender
for textured `.blend`), renders thumbnails with `usdrecord`, infers a category +
placement metadata, and emits `catalog.json` ready to upload via `rclone`. See
the pipeline README for the full workflow.

Models without their own materials are flagged in the manifest and rendered with
a neutral grey so they never show RealityKit's missing-material placeholder.

## Supported File Formats

- **USDZ (Universal Scene Description)**: Primary runtime format for 3D models
  - Supports high-quality textures and materials
  - Optimized for Apple platforms
  - Compatible with Reality Composer and other 3D tools
- **Source formats (catalog pipeline)**: `glb`/`obj`/`fbx` and Blender `.blend`
  are accepted by [Tools/catalog-pipeline/](Tools/catalog-pipeline/) and
  converted to ARKit-compatible `usdz` for the catalog

## Requirements

- visionOS 26.0+
- Mac with Apple Silicon (M1+)
- Xcode with visionOS support
- SwiftUI, RealityKit, ARKit

## Design Philosophy

DesignSphere is designed to be **simple in design and complex in feature set**. The interface follows Apple's design standards to feel familiar and easy to use, creating an important contrast with other tools in this space that often have high barriers of entry, are costly, and are needlessly complicated.

The app treats spatial design as an ongoing companion rather than a one-time demo, naturally fitting into recurring life moments such as moving, redecorating, setting up a home office, or refreshing a bedroom. By making previously saved layouts and objects always available and easy to tweak, DesignSphere becomes a tool users return to whenever their environment changes.

This is not just about designing rooms—**this is the future of spatial creativity: simple, powerful, adaptive.**

## Key Interactions & Gestures

DesignSphere leverages visionOS native gestures for intuitive spatial interactions:

- **Tap**: Select models from the catalog or in your space
- **Drag**: Move models around your room
- **Pinch & Rotate**: Scale and rotate selected models
- **Direct Manipulation**: All 3D models support natural hand interactions
- **Menu Navigation**: Eye tracking and tap gestures for UI navigation
- **Model Editing**: Precision controls for position (X, Y, Z), rotation, scale, color, and material properties

## Material System

- **Material Types**: Wood, Metal, Fabric, Leather, Custom
- **Editable Properties**:
  - Base color (RGBA)
  - Roughness
  - Metallic
  - Specular highlights
- **Texture Support**: Normal maps for wood grain, fabric weave, and leather patterns
- **Material Persistence**: Custom materials are saved with projects and restored on load

## Running the App

Clone the repo from: <https://github.com/JaimieMarch/DesignSphere/tree/sam_new>

Currently, sam_new is our active branch.

1. Open [Demo App.xcodeproj](Demo App.xcodeproj) in Xcode
2. Select a Vision Pro simulator or device
3. Build and run (⌘R)

The remote catalog requires a network connection on first launch to fetch the
manifest; thereafter the last-loaded catalog and any downloaded models are
served from the on-device cache.

## Testing

The project has three test layers:

- `XRShareCollaboration` package unit tests for catalog/search, remote download
  and caching, compression, placement/collision policy, model normalization,
  history, focus mode, components, and measurement state.
- `Demo App VisionTests` for project-file compatibility, settings persistence,
  backup contracts, materials/categories, and tutorial metadata.
- Python unit tests for catalog discovery, classification, conversion commands,
  thumbnail handling, hashing, and manifest generation.

Run the complete deterministic suite from the repository root:

```sh
Tools/run-tests.sh
```

To select a specific simulator, override the destination:

```sh
DESIGNSPHERE_TEST_DESTINATION='platform=visionOS Simulator,id=<simulator-uuid>' \
  Tools/run-tests.sh
```

The package tests can also be run independently:

```sh
cd Packages/XRShareCollaboration
xcodebuild test -scheme XRShareCollaboration \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=latest'
```

The live R2 integration test is skipped by default so local and CI runs remain
hermetic. Opt into it with `RUN_LIVE_CATALOG_TESTS=1 Tools/run-tests.sh`; it
loads the hosted catalog and downloads a model, so it requires network access.

## Known Limitations

- **World Anchor Persistence**: Projects anchored to physical locations work best when loaded in the same room where they were created
- **Edit Panel in Simulator**: the floating edit panel renders via RealityView attachments and does **not** draw in the visionOS simulator (a simulator limitation, not the app); the open/position logic is verified, and it is expected to render on a physical device
- **Model Import**: Currently only supports USDZ format; OBJ and FBX support planned for future releases
- **SharePlay**: UI implemented but peer-to-peer networking functionality in development
- **Design Assistant**: Recommendations are on-device and work everywhere; the natural-language box requires Apple-Intelligence hardware (visionOS 26) and so does not appear in the simulator
- **Simulator Testing**: Full spatial tracking features require physical Vision Pro hardware; simulator provides limited AR capabilities

## Development Status

**DesignSphere is currently a work in progress**, developed as a course project for CPSC 575. While the core design experience is functional and demonstrates the vision for spatial computing in interior design, several advanced features remain in various stages of development.

### Future Development Roadmap

Our roadmap is driven by both user feedback and the evolution of spatial computing capabilities:

- **SharePlay Integration**: Fully implement peer-to-peer collaboration with synchronized model manipulation, allowing multiple users to design together in real-time
- **AI Design Assistant**: Integrate AI-powered suggestions for furniture placement, color coordination, and style recommendations based on room dimensions and user preferences
- **Enhanced Measurement Tools**: Complete ruler functionality, automated room dimension detection, and collision/spacing warnings
- **Focus Mode Completion**: Implement passthrough filtering to remove real-world furniture, and create curated neutral environments for distraction-free design
- **LiDAR Scanning System**: Build a complete scanning workflow to capture existing furniture with the Vision Pro's LiDAR sensor and convert it into reusable, editable 3D models
- **CloudKit Integration**: Migrate from local storage to cloud-based project management, enabling cross-device synchronization and family sharing of design projects
- **Expanded Model Library**: Curate and integrate hundreds of additional furniture models across more categories (outdoor, office, kids, etc.)
- **Performance Optimization**: Implement advanced occlusion culling, level-of-detail (LOD) systems, and progressive loading for larger projects
- **Voice Commands**: Implement hands-free operation with natural language commands for model placement, editing, and project management
- **Accessibility Enhancements**: Add VoiceOver support, high-contrast modes, and alternative input methods for users with different accessibility needs
- **Commercial Space Tools**: Develop specialized furniture libraries and layout templates for retail stores, restaurants, salons, cafés, and boutiques
- **Professional Features**: Add client presentation modes, measurement annotations, export to CAD formats, and cost estimation tools for interior designers and architects
- **Furniture Brand Partnerships**: Create co-marketing opportunities with furniture retailers, allowing users to "try before they buy" with brand-specific AR catalogs that link directly to purchase
- **Multi-room Projects**: Support for designing entire homes or multi-floor commercial spaces with room-to-room navigation
- **Advanced Materials Library**: Expand material options with fabric patterns, wallpapers, flooring options, and real-world brand partnerships for authentic textures
- **AR Sharing & Social**: Enable users to share their designs as AR experiences on social media, creating viral marketing opportunities and community engagement
- **Cross-platform Support**: Extend to iPad and iPhone with ARKit for broader accessibility, allowing users to preview designs before accessing Vision Pro
- **Smart Home Integration**: Connect with HomeKit and smart lighting systems to preview designs with realistic lighting conditions
- **Real-time Rendering Upgrades**: Leverage future visionOS updates for improved ray tracing, better passthrough quality, and enhanced spatial audio
- **Marketplace Ecosystem**: Create a user-generated content marketplace where designers can sell custom models, templates, and design packages
- **Enterprise Solutions**: Develop B2B offerings for architecture firms, real estate agencies, and facility management companies

### WISHLIST

- ~~move the catalogue to the cloud - keep local sandboxed storage for user uploads/spatial web~~ — **done**: catalog hosted on Cloudflare R2 with lazy download + on-device caching ([docs/remote-catalog.md](docs/remote-catalog.md))
- ~~intent-aware catalog search~~ — **done** (`ModelSearchEngine`, see test suite)
- verify the floating edit panel on a physical device (renders via RealityView attachments; does not draw in the simulator)
- finalize all required functionality for acceptable release version
- add removed screens back into workflow
- complete the measurement tools (manager + UI largely built; verify/polish)
- go through apple guidelines and conform
- ~~AI design assistant: wire the assistant shell to real catalog-driven suggestions~~ — **done**: on-device recommender + optional Foundation Models layer ([docs/design-assistant.md](docs/design-assistant.md))

### Contributing to Development

As this is an active course project, we're continuously iterating based on:

- Testing and feedback sessions
- Vision Pro platform updates and new API capabilities
- Performance profiling and optimization opportunities
- Technological advancements in spatial computing

The roadmap remains flexible and will adapt as we learn more about how users interact with spatial design tools and as Apple's visionOS platform matures.

AUDIT FIXES IS THE LAST STABLE COMMIT PRE-REWORKED VERSION OF EDIT MODEL VIEW

## Credits

This project is powered by XRShare - with special thanks to:
Dr. Christian Jacob
Joanna Lin
Ali Kara
Lindsay Lab
BlenderKit
The Base Mesh
Poly Haven

**DesignSphere** was developed for CPSC 575 by:

- Sam
- Jaimie
- Mishela
- Thi

---

*See Your Vision. From Within.*
