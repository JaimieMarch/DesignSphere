# Production privacy declaration

Decision date: July 26, 2026  
Applies to: DesignSphere 1.0 and the Cloudflare-hosted production catalog

## Decision

Do **not** select “Data Not Collected” in App Store Connect while catalog files
are delivered through Cloudflare. Use this declaration instead:

| App Store Connect answer | Selection |
| --- | --- |
| Data type | Other Diagnostic Data |
| Collected | Yes |
| Purpose | App Functionality |
| Linked to the user's identity | No |
| Used for tracking | No |

No other data type is transmitted by DesignSphere. Projects, user imports,
backups, preferences, spatial information, hand data, favorites, and
Foundation Models prompts remain on-device unless the user explicitly exports a
file through a system interface.

## Evidence and reasoning

DesignSphere retrieves a manifest, thumbnails, and selected USDZ files from a
public Cloudflare R2 endpoint. A network request necessarily gives Cloudflare
the source IP address and requested object. Cloudflare's current documentation
establishes that:

- [Customer Logs are traffic metadata](https://developers.cloudflare.com/data-localization/metadata-boundary/)
  such as request URLs and timestamps that may identify end users, and are
  stored by Cloudflare unless their location is restricted by an Enterprise
  metadata boundary.
- Cloudflare's [Data Processing Addendum](https://www.cloudflare.com/cloudflare-customer-dpa/)
  identifies IP addresses as an example of personal data in Customer Logs.
- [R2 metrics and analytics](https://developers.cloudflare.com/r2/platform/metrics-analytics/)
  retain request-operation fields such as object name, status, and timestamp
  for 31 days. This dataset does not itself document an IP-address field, but it
  confirms that request metadata persists beyond servicing the request.
- Apple's [App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/)
  says data retained by the developer or a third-party partner beyond the time
  required to service a request is collected. Apple specifically says retained
  IP-address data must be declared according to its use.

The conservative, internally consistent classification is **Other Diagnostic
Data** for **App Functionality**: Cloudflare uses the metadata to deliver and
secure files, diagnose failures, and maintain availability. It is not linked by
DesignSphere because the app has no account, user ID, advertising ID, or server
profile. It is not used for tracking, advertising, or product personalization.

## Repository alignment

- `Demo App Vision/PrivacyInfo.xcprivacy` contains the same data type, purpose,
  linking, and tracking values.
- The in-app policy and `docs/privacy-policy.md` disclose Cloudflare processing
  and the same App Store classification.
- App Store Connect must use the table above; do not copy the older “Data Not
  Collected” recommendation from release notes or previous checklist versions.

Re-run this decision if the catalog host changes, a Worker or analytics product
is added, Logpush is enabled, user uploads are introduced, or Cloudflare's
logging configuration or terms materially change.
