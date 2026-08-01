# Home Screen & Lock Screen Widgets — Planning

**Status: design only, not implemented.** No `WidgetKit` extension target exists yet. This
doc scopes the work before any Xcode project changes are made, in the same spirit as the
"Decisions made by default" table in the root `README.md`.

## Scope

Two widget surfaces, one extension target:

- **Home Screen widgets** (`systemSmall` / `systemMedium`) — WidgetKit, iOS 16+.
- **Lock Screen widgets** (`accessoryRectangular` / `accessoryCircular` / `accessoryInline`) —
  also WidgetKit, also iOS 16+. **StandBy is not separately built.** On iOS 17+, StandBy reuses
  whatever Lock Screen accessory families a widget already supports — so shipping the Lock
  Screen families gets StandBy for free without raising the app's iOS 16.0 deployment target or
  writing StandBy-specific code. This is the one decision in this doc that removes work rather
  than adding it, so it's called out up front.

Explicitly out of scope for this round: Live Activities / Dynamic Island (a separate
ActivityKit feature, not requested) and Aurora/space-weather content (Phase 2 per the root
README — no data plumbing for it exists yet).

**Primary content: "currently overhead / live tracking."** The widget answers "what's up there
right now," not "when's the next pass" (that's a natural Phase 2 widget mode once this ships,
reusing the same `PassPredictor` math already in `OverheadCore`).

## Why this is feasible without a backend or extra network calls

`OverheadCore` is already a plain Swift package with no UIKit/ARKit dependency, and
`SatelliteTrackingService` already separates concerns in exactly the way a widget needs:

- Position math (`SatellitePosition.snapshot`) is pure, deterministic SGP4 propagation — no
  network, cheap to call from a widget extension process on a timer.
- Network fetches (`CelestrakClient`) are decoupled from position math and only need to run
  every ~6 hours (`SatelliteTrackingService.catalogRefreshInterval`).

So the widget extension should **never fetch TLEs itself**. It reads whatever TLE text the main
app already cached (`TLECache`) and re-propagates locally, mirroring `positionLoop` in
`SatelliteTrackingService`. This keeps the extension's memory/CPU footprint inside WidgetKit's
tight per-refresh budget and avoids a second Celestrak client hitting the same IP-based rate
limit noted in the README.

## Data sharing: App Group

The app and the widget extension are separate processes with separate sandboxes. Two things
need to cross that boundary, both one-way (app → widget, never the reverse):

1. **Cached TLE text.** `TLECache` currently writes to `Application Support` inside the main
   app's container — invisible to an extension. It needs to move to the shared App Group
   container (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`), e.g.
   `group.com.frontend720.overhead`. This is a small, low-risk change: `TLECache`'s call sites
   don't change, only the `directory` computed property's base URL.
2. **Last-known observer location.** Widgets have no reliable way to request fresh location
   themselves (no foreground, tight execution budget) and requesting it from a widget extension
   means a second location-permission surface to reason about. Simpler: `LocationService`
   already receives location updates in the main app — have it write the last known
   lat/lon/timestamp to `UserDefaults(suiteName: appGroup)` whenever it updates. The widget's
   `TimelineProvider` reads that cached location instead of touching `CoreLocation` at all. A
   stale-location fallback ("open the app to update your location") is needed for the
   first-run / location-never-granted case.

Both targets need the same App Group entitlement. Neither needs a new backend call or schema —
this is purely local IPC via the shared container.

## "Currently overhead" content logic

Reuses the existing clutter-limiting priority from `SatelliteTrackingService.limitClutter`
rather than inventing a new rule:

1. If the ISS is above the horizon, it's always the headline object (matches the app's own
   priority — it's the one users came for).
2. Else, the nearest visible Starlink by range.
3. Else, nothing is visible — fall back to `PassPredictor.nextPasses` for the ISS and show a
   countdown ("ISS visible in 42m") instead of a blank widget.

Family-by-family rendering of that same headline object/state:

| Family | Content |
|---|---|
| `systemSmall` | Object name + elevation/compass direction, or next-pass countdown |
| `systemMedium` | Object name + direction/altitude, plus a secondary line (velocity or launch year) |
| `accessoryRectangular` | Compact two-line text (name + direction, or countdown) |
| `accessoryCircular` | Icon + a gauge-style countdown to next pass |
| `accessoryInline` | Single line: `"ISS overhead, NW ↗"` or `"ISS in 42m"` |

## Timeline / refresh strategy — the part that needs real-device tuning

SGP4 propagation being deterministic and network-free means `TimelineProvider.getTimeline` can
generate a **batch of future entries in one call** rather than requesting a reload every time
the display needs to change — e.g. compute entries at 60s resolution for the next 10–15
minutes, then schedule the next `getTimeline` call for `.after(windowEnd)`. This directly
mirrors what `positionLoop` already does at a 2s cadence in-app, just coarsened to fit
WidgetKit's refresh budget (typically on the order of tens of reloads/day, not
seconds-resolution).

This is flagged as an **open question requiring real-device measurement**, for the same reason
the README flags AR verification as unverified: this environment has no full Xcode/device, so
budget tuning (window length, entry resolution, whether to also call
`WidgetCenter.shared.reloadTimelines` from the app when a fresh catalog fetch lands) can't be
validated here. Ship a conservative first pass (e.g. 15-minute windows, 1-minute entries) and
tune from actual WidgetKit budget behavior on a device.

## Target changes required (not yet made)

- New `OverheadWidgets` extension target in `project.yml` (XcodeGen `type: appex`,
  `com.apple.widgetkit-extension` `NSExtensionPointIdentifier`), embedded in `Overhead` via
  `dependencies: [{ target: OverheadWidgets, embed: true }]`.
- Bundle ID `com.frontend720.overhead.widgets`.
- `OverheadWidgets` depends on the `OverheadCore` package directly (same as `Overhead` does)
  for `TrackedObject`, `SatellitePosition`, `PassPredictor`, `TLECache`.
- App Group entitlement (`group.com.frontend720.overhead`) added to **both** targets — new
  `.entitlements` files referenced via `CODE_SIGN_ENTITLEMENTS`, since neither target has one
  today.
- `TLECache` directory source changed to the App Group container (see above).
- `LocationService` writes last-known location to the shared `UserDefaults` suite.

None of this is applied yet. Given this repo currently can't be built or run in this
environment (per the root README's "Not yet done / not yet verified" list — no full Xcode
here), hand-editing `project.yml` for a new extension target and entitlements without being
able to `xcodegen generate` + build + verify on a real Mac is more likely to produce a broken
project state than a working one. Recommend making these changes in an environment where the
result can actually be built before merging.

## Suggested phasing

1. **Foundational plumbing** (testable today, no widget yet): move `TLECache` to the App Group
   container, add location caching to `UserDefaults(suiteName:)` in `LocationService`. Unit
   tests in `OverheadCoreTests` can cover the cache path change directly.
2. **Widget scaffold**: `OverheadWidgets` target, Home Screen families only, static/short
   timeline reading the shared cache.
3. **Lock Screen families** (StandBy comes free on iOS 17+ once these exist) + the
   next-pass-countdown fallback state via `PassPredictor`.
4. **Budget tuning** from real device usage, then optionally a widget configuration
   (`AppIntent`) to let users pin Starlink vs. ISS priority.

## Open questions

- [ ] Confirm App Group identifier (`group.com.frontend720.overhead` assumed above, matching
  the existing `com.frontend720.overhead` bundle ID prefix).
- [ ] Decide whether the widget needs its own `NSLocationWhenInUseUsageDescription` framing, or
  whether "reads the app's last-known location" is sufficient disclosure (likely yes, since no
  new permission prompt is introduced).
- [ ] Real-device WidgetKit refresh-budget tuning (see Timeline section) — cannot be validated
  in this environment.
- [ ] Should the "nothing visible, next pass in Xm" fallback also cover Starlink, or stay
  ISS-only to keep the countdown meaningful (Starlink passes are frequent and less
  individually notable)?
