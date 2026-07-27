# DesignSphere Privacy Policy

**Effective date:** July 26, 2026  
**Last updated:** July 26, 2026

DesignSphere is an Apple Vision Pro interior-design application maintained by
the DesignSphere project team. This policy explains how the app handles data.

## Summary

DesignSphere has no user accounts, advertising, or third-party analytics. The
app does not sell personal information and does not use data to track people
across apps or websites.

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

As with other Internet services, Cloudflare may process an IP address and
request metadata to deliver, secure, and operate the service. DesignSphere does
not use catalog requests for advertising, cross-app tracking, or user profiles.
Cloudflare's handling of service data is governed by its
[privacy policy](https://www.cloudflare.com/privacypolicy/).

The DesignSphere team must verify the production Cloudflare logging and
retention configuration before making a final App Store privacy declaration.

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
