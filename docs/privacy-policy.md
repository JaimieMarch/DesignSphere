# DesignSphere Privacy Policy

**Effective date:** July 26, 2026  
**Last updated:** July 26, 2026

DesignSphere is an Apple Vision Pro interior-design application maintained by
the DesignSphere project team. This policy explains how the app handles data.

## Summary

DesignSphere has no user accounts, advertising, or behavioral analytics. The
app does not sell personal information and does not use data to track people
across apps or websites. Cloudflare processes limited network and diagnostic
metadata when it delivers the remote catalog, as described below.

## Data stored on the device

DesignSphere can store the following information locally:

- saved room projects and model placements;
- user-imported USDZ model files;
- world-anchor identifiers and transforms used to restore room alignment;
- favorites, accessibility settings, onboarding state, and Labs preferences;
- a cached remote-catalog manifest, thumbnails, and downloaded USDZ models;
- backup files that the user explicitly creates and saves to a chosen location.

This information remains on the device unless the user exports a backup or
chooses to share a file through a system-provided interface. Project data,
imports, anchors, and favorites can be deleted from **Settings > Manage Local
Data**. Removing the app deletes its app-container data. Exported backups remain
at their chosen location until the user deletes them there.

Downloaded catalog content is stored as operating-system cache data. It may be
removed automatically to recover storage space.

## Spatial information and permissions

DesignSphere uses Apple spatial APIs to understand surfaces, maintain world
placement, and support system interactions. Spatial information is processed on
the device and is not uploaded by DesignSphere. The app does not record camera,
microphone, or hand-tracking footage.

Spatial access can be denied through the system permission prompt or changed in
visionOS Settings. Features that require spatial understanding may not work when
access is denied.

## Remote catalog and network requests

DesignSphere contacts a catalog hosted on Cloudflare infrastructure to download:

- `catalog.json`, which describes available furniture and decor;
- model thumbnails; and
- USDZ model files selected for placement.

These HTTPS requests necessarily expose the requesting IP address to Cloudflare.
Cloudflare may retain customer or service logs containing an IP address, request
URL/object name, timestamp, response status, and related security or diagnostic
metadata. Cloudflare documents 31-day retention for R2 operational metrics; its
other service-log retention is governed by its contracts and
[privacy policy](https://www.cloudflare.com/privacypolicy/).

This limited metadata is used only to deliver the requested files, protect the
service, diagnose failures, and maintain availability. DesignSphere has no
account or advertising identifier with which to link it, and does not use it for
advertising, cross-app tracking, behavioral analytics, or user profiles. The App
Store privacy declaration therefore reports **Other Diagnostic Data**, used for
**App Functionality**, **not linked to the user**, and **not used for tracking**.
No project, imported model, backup, spatial map, hand data, or design-assistant
prompt is sent with a catalog request.

## On-device design assistant

When available, natural-language design requests use Apple's Foundation Models
on the device. DesignSphere does not send those requests to a DesignSphere
server. Quick-action recommendations are also computed locally.

## Backups

A DesignSphere backup can contain categories selected by the user, including
projects, imported models, world anchors, favorites, and preferences. Backups
are created only on request and saved to a location selected through the system
file interface. Anyone with access to a backup may be able to read or restore
its contents, so backups should be stored and shared carefully.

## Children

DesignSphere is not designed to collect personal information from children or
from any other user.

## Changes to this policy

Material changes will be published on this page and reflected in the in-app
policy. The effective date above will be updated.

## Contact

For privacy questions or requests, use the
[DesignSphere support tracker](https://github.com/JaimieMarch/DesignSphere/issues/new).
Do not include private project files, backup files, room information, or other
sensitive personal information in a public GitHub issue.
