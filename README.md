# Design Sphere App
**See Your Vision. From Within.**

DesignSphere is an interior design app built from the ground up for the Apple Vision Pro that allows users to design or customize their space in real time, in real space. The app reimagines interior design through spatial computing, turning any room into a blank canvas where furniture and décor appear true to scale and true to life.

The app eliminates the struggle of visualizing furniture fit, costly big commitments, painful returns, and the physical effort of moving items around. Instead of being limited by traditional screens, DesignSphere uses intuitive gesture-based controls to let users interact with high-fidelity 3D models that respond naturally to their environment. Objects snap into place respecting room geometry, with built-in spatial recognition understanding room size and surfaces to position items correctly.

Designed for students, interior designers, real estate stagers, and businesses alike, DesignSphere adapts to suit different needs. Whether you're a student furnishing your first apartment, a designer presenting concepts to clients, or a business owner planning a retail layout, DesignSphere provides the tools to plan, visualize, and test interior layouts efficiently—making spatial computing practical and accessible for everyday design.

## Features

### Core Functionality
- **Intuitive Interface**: Clean, floating translucent menus that adhere to Apple's design language, with gesture-based controls that stay out of the way while remaining easily accessible
- **Model Library**: Browse a comprehensive catalog of furniture and décor with favoriting, previews, and 3D model thumbnails 
- **Advanced Model Editing**: Comprehensive editing tools allowing users to adjust size, position, rotation, style, texture, and color of each item
- **Spatial Recognition**: Built-in spatial APIs anchor objects with incredible accuracy, matching scale and perspective to your room's exact dimensions
- **Project Management**: Save and organize multiple room layouts, create different versions to compare design options, and return to previous projects anytime
- **Location-Aware Loading**: The app can recognize a space and automatically load the related design when you return

### Additional Features (UI Implemented, Functionality In Development)
- **Model Import**: Import custom USDZ files from your device to expand the furniture library
- **Focus Modes**: Interface for toggling real-world item visibility and accessing neutral design spaces
- **Measurement Tools**: UI for displaying room dimensions and object measurements with ruler functionality
- **AI Design Assistant**: Voice-activated assistant interface for design suggestions and guidance
- **SharePlay Collaboration**: Multi-user session interface with session codes for real-time collaboration

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

## Included Model Library

The app comes with a starter library of 9 basic USDZ models:
- 65" TV
- Chair
- Chandelier
- Closet
- Coffee Table
- Couch
- Dinner Table
- Stool
- Vase

Users can expand this library by importing custom USDZ files through the Import feature. This library will constantly be expanded upon, and improved in quality. 

## Supported File Formats

- **USDZ (Universal Scene Description)**: Primary format for 3D models
  - Supports high-quality textures and materials
  - Optimized for Apple platforms
  - Compatible with Reality Composer and other 3D tools

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

Clone the repo from: https://github.com/JaimieMarch/DesignSphere/tree/sam_new

Currently, sam_new is currently our active branch. 

1. Open [DesignSphere.xcodeproj](DesignSphere.xcodeproj) in Xcode
2. Select a Vision Pro simulator or device
3. Build and run (⌘R)

## Known Limitations

- **World Anchor Persistence**: Projects anchored to physical locations work best when loaded in the same room where they were created
- **Model Import**: Currently only supports USDZ format; OBJ and FBX support planned for future releases
- **SharePlay**: UI implemented but peer-to-peer networking functionality in development
- **AI Assistant**: Voice interface present but AI integration pending
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

### Contributing to Development

As this is an active course project, we're continuously iterating based on:
- Testing and feedback sessions
- Vision Pro platform updates and new API capabilities
- Performance profiling and optimization opportunities
- Technological advancements in spatial computing

The roadmap remains flexible and will adapt as we learn more about how users interact with spatial design tools and as Apple's visionOS platform matures.

## Credits

This project is powered by XRShare - with special thanks to:
Dr. Christian Jacob
Joanna Lin
Ali Kara
Lindsay Lab

**DesignSphere** was developed for CPSC 575 by:
- Sam
- Jaimie
- Mishela
- Thi

---

*See Your Vision. From Within.*
