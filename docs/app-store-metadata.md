# App Store Connect Metadata Packet

_Prepared July 26, 2026; release handoff updated October 11, 2026 for DesignSphere 1.0 (build 1)._

This is the copy-ready source of truth for the first visionOS submission. Do a
final comparison against the uploaded build before pasting it into App Store
Connect. Do not add roadmap features to the product page or screenshots.

Apple currently limits the name and subtitle to 30 characters each, the
description to 4,000 characters, promotional text to 170 characters, and
keywords to 100 bytes. See Apple's
[app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
and
[platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
references.

## App record

| Field | Value or action |
| --- | --- |
| Name | `DesignSphere` |
| Bundle ID | `com.designsphere.app` |
| SKU | Suggested: `DesignSphere-visionOS-1` (choose carefully; Apple does not allow changing it later) |
| Primary language | English (Canada) |
| Primary category | Lifestyle. **Must be set here** — `LSApplicationCategoryType` is declared in `DesignSphere-Info.plist` but Xcode strips it from the built bundle (it is a macOS-only key), so nothing is inherited from the build. Verified against the built app 2026-08-30. |
| Secondary category | Graphics & Design |
| Version | `1.0` |
| Build | `1` — increment before a replacement upload |
| Copyright | **TODO:** `2026 <legal owner name>` |
| Price and availability | **TODO:** owner decision |
| Content rights | The app contains third-party catalog content and has the necessary rights. Attach or link `asset-license-audit.md` if Apple asks for evidence. |
| License agreement | Apple's standard EULA, unless the legal owner chooses a custom agreement |

## Product-page copy

### Subtitle

`Design Rooms in Your Space`

### Promotional text

`Plan rooms at true scale with 180+ furniture and décor models, spatial measurement tools, customizable finishes, saved layouts, and on-device design help.`

### Keywords

`interior,room planner,furniture,decor,spatial,layout,measure,home,architecture,immersive`

Do not add `DesignSphere`, Apple trademarks, competitor names, SharePlay,
LiDAR, voice commands, or other disabled/roadmap terms.

### Description

```text
DesignSphere turns Apple Vision Pro into a spatial interior-design workspace. Explore more than 180 furniture and décor models, place them at true scale in your surroundings, and test a layout before moving or buying real furniture.

Plan with spatial tools:

• Search and filter a catalog of seating, tables, lighting, storage, beds, media, and décor.
• Place, move, rotate, resize, recolor, and apply materials to models with natural controls.
• Show object dimensions, measure distances between items, and use a virtual ruler with metric or imperial units.
• Get on-device furniture suggestions and arrange starter layouts with Design Assistant. Natural-language requests are available on supported Apple Intelligence hardware.
• Save multiple room projects and restore their placements when you return.
• Import your own USDZ models and create local backups of selected app data.
• Enter a themed, resizable Focus Mode when you want a neutral design space.

DesignSphere has no accounts, advertising, or subscriptions. Projects and imported models stay on your device unless you explicitly export a backup. The catalog requires a network connection on first use; model download sizes are shown before placement, and downloaded models are cached on device.
```

## Public URLs

Both policy and support pages returned HTTP 200 during the October 11 audit.
Open them in a signed-out browser before entering them in App Store Connect.

| Field | Prepared URL | Status |
| --- | --- | --- |
| Privacy Policy URL | `https://github.com/JaimieMarch/DesignSphere/blob/main/docs/privacy-policy.md` | **HTTP 200 verified October 11, 2026** |
| Support URL | `https://github.com/JaimieMarch/DesignSphere/blob/main/docs/support.md` | **HTTP 200 verified October 11, 2026** |
| Marketing URL | `https://github.com/JaimieMarch/DesignSphere` | Optional; verify before use |

Before submission, the legal owner must decide whether the public support page
needs an email address, phone number, or legal address for the storefronts in
scope. Apple requires the Support URL to provide real contact information as
applicable under local law; do not invent or commit personal contact details.

## App privacy

Use the exact prepared answers in
[production-privacy-declaration.md](production-privacy-declaration.md):

- select **Other Diagnostic Data**;
- purpose: **App Functionality**;
- not linked to identity;
- not used for tracking; and
- do not select **Data Not Collected** while Cloudflare processes catalog
  request metadata.

The privacy manifest and in-app policy already use the same declaration.

## Age rating

Answer from the submitted build, not from roadmap plans. For the current build:

- In-App Controls: no parental controls and no age assurance.
- Capabilities: no unrestricted web access, broadly distributed user-generated
  content, social media, messaging/chat, or advertising. Local USDZ import and
  local project creation are not broad distribution of user-generated content.
- Mature Themes, Medical or Wellness, Sexuality or Nudity, Violence, and
  Chance-Based Activities: **None** for every item.
- Made for Kids / override: **Not Applicable**. Apple does not permit the Kids
  category for visionOS apps.

These answers should calculate to the lowest applicable rating (expected 4+),
but save the rating Apple actually calculates rather than manually promising a
specific regional result. Apple's questionnaire and regional calculation are
documented in
[Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating).

## App motion information

Select **No, this app doesn't contain high motion** for the current build. The
app has no automatic camera motion, sudden viewpoint changes, or forced rapid
turns; users move their own viewpoint and directly manipulate room objects.
Confirm this answer during the physical-device pass. App motion information is
required for every visionOS submission.

## Screenshots

Apple accepts one to ten Apple Vision Pro screenshots. Each submitted image
must be exactly **3840 × 2160 pixels**, use JPEG/JPG/PNG, and have no alpha
channel. Accurate Simulator captures are allowed if resized and cropped to the
upload specification; Apple recommends Developer Capture on physical hardware
for the highest quality. See Apple's
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
and
[visionOS submission guidance](https://developer.apple.com/visionos/submit/).

Capture five or six uncluttered, privacy-safe scenes in this order:

1. A strong hero scene with several placed models and the catalog visible.
2. Intent-aware search and category/finish filters showing the 180+ catalog.
3. A selected model with the edit panel showing scale, color, or material tools.
4. Object dimensions, distance measurement, or the virtual ruler in use.
5. Design Assistant recommendations or a generated starter layout.
6. Saved projects or the themed Focus Mode, if the composition is stronger than
   one of the scenes above.

Do not show SharePlay, LiDAR scanning, voice commands, private room details,
real account information, debug UI, a failed download, or features that differ
from the submitted build. Keep the window straight and the surroundings clean.

### Capture recipe (verified 2026-08-30)

The visionOS Simulator captures at **3840 × 2160** on the audited setup.
Export JPEG directly so the screenshot has no alpha channel:

```sh
xcrun simctl bootstatus <device-udid> -b
xcrun simctl install booted /path/to/DesignSphere.app
# Skip the first-run sheet using launch arguments.
xcrun simctl launch booted com.designsphere.app -settings.onboardingCompleted YES
xcrun simctl io booted screenshot --type=jpeg shot.jpg
sips -g pixelWidth -g pixelHeight -g hasAlpha shot.jpg
```

Give the app ~25 s after launch before capturing: the catalog fetch has a 20 s
timeout and the grid is empty until it resolves.

Two limitations found while capturing:

- **Debug builds can start on another tab:** add `-debug.initialTab settings`
  (or `details`) to the launch command. Release builds ignore it.
- **Scripted taps do not work.** Driving the Simulator with `osascript`/System
  Events needs Accessibility permission for the calling terminal (System
  Settings → Privacy & Security → Accessibility). Without it, only states
  reachable from launch arguments or the container can be captured; anything
  requiring navigation has to be captured by hand.
- Untextured "Customizable" models render as neutral grey by design. Prefer
  textured pieces in hero shots so the grid does not read as broken.

## App Review information

### Contact

**TODO in App Store Connect:** enter the real review contact's name, monitored
email address, and phone number. Do not store private review contact data in
this public repository.

### Sign-in

No sign-in or demo account is required.

### Review notes

```text
DesignSphere is a native visionOS interior-design app with no login, in-app purchases, advertising, or subscriptions.

On first launch, complete or skip onboarding and grant the requested spatial permissions. The Browse screen loads catalog metadata and thumbnails from Cloudflare R2. Tap a catalog item to download its USDZ model on first use and place it in the space; the UI discloses the download size, reports progress, verifies the file, and caches it locally. A Retry action is available for catalog or model download failures.

Core review path: Browse > select a model > place it > select the placed model > Edit. The bottom toolbar provides undo/redo, Focus Mode, USDZ import, Design Assistant, collision controls, and Measurement. Projects are saved and loaded from Details. Backup export/import and local-data deletion are in Settings.

No sign-in or special configuration is required. Natural-language Design Assistant input only appears on Apple Intelligence-capable hardware; its quick-action recommendations remain available without it. SharePlay, LiDAR scanning, and voice commands are not part of this build and are not exposed in the UI.

The app processes project, imported-model, spatial, and assistant data on device. Cloudflare processes limited request/diagnostic metadata to deliver catalog files; App Store privacy answers declare Other Diagnostic Data used for App Functionality, not linked to the user and not used for tracking.
```

## Final Connect-only tasks

- [ ] Create the app record with the legal owner's Apple Developer account.
- [ ] Confirm the SKU, price, territories, DSA trader status, tax category, and
  legal copyright owner.
- [ ] Enter the verified public policy and support URLs.
- [ ] Paste the product-page copy and privacy answers.
- [ ] Complete the age-rating and app-motion questionnaires.
- [ ] Capture, validate, and upload the final screenshots.
- [ ] Enter private review contact details.
- [ ] Test the uploaded distribution build through TestFlight, then select the
  accepted build for App Review. TestFlight is our recommended release check,
  not a requirement to submit an app to App Review.
