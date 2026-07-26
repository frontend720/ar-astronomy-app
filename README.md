# Overhead *(working title)*
### AR Satellite & ISS Tracker — iOS

> **Elevator pitch:** Point your phone at the sky. See exactly what's flying overhead — ISS, Starlink trains, named satellites — labeled in real time via AR. Built to be both a genuinely useful sky tool and a content engine: the app *is* the demo.

---

## 0. Project Status

**Scaffolding stage.** The repo now has a buildable skeleton:

- `OverheadCore/` — a plain Swift Package (no UIKit/ARKit) with TLE parsing, a Celestrak client, SGP4-based position math, and a naive pass predictor. Builds and unit-tests clean with `swift build` / `swift test` on any Mac, no Xcode project needed.
- `Overhead/` + `Overhead.xcodeproj` — the SwiftUI + ARKit iOS app shell: permission flow, live AR sky overlay, tap-for-info card. Generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) — edit `project.yml` and re-run `xcodegen generate` rather than hand-editing the `.xcodeproj`.

**Not yet done / not yet verified:**
- Never built or run in Xcode/Simulator/device — the environment this was scaffolded in only has Xcode's Command Line Tools active (no full Xcode), so `xcodebuild` isn't available there. Open `Overhead.xcodeproj` in Xcode on a real Mac to build.
- ARKit requires physical camera hardware — the AR view **cannot** be tested in the iOS Simulator at all. First real verification has to happen on a device.
- Pass prediction is a brute-force time-stepper (30s resolution) — fine for a "visible in ~6 min" notification, not for anything requiring second-level precision. No notification scheduling (`UNUserNotificationCenter`) is wired up yet, just the underlying math.
- No app icon, launch screen content, or visual identity — `UILaunchScreen` is an empty placeholder.
- No Xcode signing team is set (`DEVELOPMENT_TEAM: ""` in `project.yml`) — set your team in Xcode's Signing & Capabilities tab before running on a device.

### Decisions made by default while scaffolding (flagged for override)

| Decision | Default chosen | Why |
|---|---|---|
| SGP4 library | [SatelliteKit](https://github.com/gavineadie/SatelliteKit) (MIT, v2.1.2) | Actively maintained, has a built-in topocentric look-angle function (`topPosition` → azimuth/elevation/range) — exactly what AR placement needs — rather than requiring hand-rolled ECI→horizon math on top of a bare propagator. Verified it builds via SPM before committing to it. |
| MVP object list | ISS + Starlink only | Matches the roadmap's suggested MVP scope; Celestrak's "stations" group actually includes Tiangong etc., so `CelestrakClient.fetchISS()` filters that group down to NORAD ID 25544 specifically. |
| Launch info source | Parsed from the TLE's international designator (e.g. `1998-067A` → 1998) | Avoids a second data source for a "launch year" field — Celestrak TLEs already carry it. |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) + `project.yml`, rather than a hand-written `.xcodeproj` | Avoids hand-authoring pbxproj XML; `project.yml` is the source of truth and diffs cleanly in git. |
| iOS deployment target | 16.0 | Matches the minimum needed for `Grid` and `.presentationDetents` in the info card; no reason found to require newer. |
| TLE delivery model | Direct client → Celestrak (no backend) | Fine for solo testing. Celestrak rate-limits by IP: every user's phone hits Celestrak directly, so a busy shared network (or Celestrak tightening limits) can block the whole app for everyone — not just the one device. The right fix before real distribution is a lightweight backend that fetches/caches TLEs on a schedule (~6 h is plenty fresh) and serves them to clients. Celestrak then sees one well-behaved requester regardless of install count. Punted until closer to real distribution; exponential backoff (30 min → 2 hr + jitter) is in place to avoid aggravating the block in the meantime. |
| Visual identity | Not yet decided (open question below, unchanged) | Out of scope for scaffolding. |

---

## 1. Why This Project

Two forces converged on this idea:

- **Content-market fit.** Short-form video rewards apps that produce a visually striking 5–15 second moment. Utility apps with quiz-style or list-based UI (e.g. test-prep flashcards) don't survive the scroll — nobody stops for a form. Space content, by contrast, is one of the most reliably viral evergreen niches across TikTok, Reels, and Shorts.
- **Cheap to build, high motivation.** The core data (satellite orbital elements, space weather) is free and well-documented, the build is scoped small enough to ship fast, and it's a project the builder is genuinely excited about — which matters more than it sounds for solo-dev follow-through.

This is why the EMT prep app concept was shelved (not killed) while it goes through peer review, in favor of shipping this first.

---

## 2. Core Concept

The flagship feature is **AR sky overlay for live satellite tracking**:

1. User holds their phone up at dusk (the ideal viewing window — dark sky, satellites still catching sunlight).
2. The app uses device orientation + GPS to align the camera view with real orbital positions.
3. As the ISS, a Starlink train, or another tracked object crosses the field of view, the app labels it live on-screen.
4. That moment — phone up, object crossing, name popping up in real time — is the "money shot": a natural, unscripted scroll-stopper that requires zero editing skill to capture.

**Content format this enables:** *"POV: you know exactly when the ISS flies over your house."* One real pass, filmed once, can be cut into a week of content (the pass itself, the countdown, the reaction, the explainer).

**The personality hook:** an "ex-satellite technician built the app that tracks satellites" narrative gives the founder a built-in on-camera character, not just a product demo. Authenticity + expertise is the differentiator against generic sky-map apps.

---

## 3. Feature Roadmap

### Phase 1 — MVP (Flagship)
**Satellite Tracker + AR Overlay**
- Real-time position tracking for ISS + major Starlink launches (expandable to any TLE-tracked object)
- AR camera overlay with live object labeling
- Pass prediction / notifications ("ISS visible over you in 6 minutes")
- Basic object info card on tap (altitude, velocity, launch info)

### Phase 2 — Premium Add-On
**Aurora / Space Weather Alerts**
- Push alerts on elevated geomagnetic activity (Kp index thresholds) for the user's location
- Not a standalone lead feature — auroras can't be scheduled, so this can't carry a content calendar on its own
- Strongest as a retention/premium hook: *"my app pinged me and I drove out and caught this"* is a powerful format when conditions cooperate, but it's a bonus, not the pitch

### Phase 3 — Slow Burn
**Astrophotography Planner**
- Timelapse / Milky Way shot planning tools (moon phase, light pollution, object visibility windows)
- Deferred: this is a utility feature that sells *the results a user gets*, not the app itself. Works far better once there's already an audience that trusts the brand — premature as a launch feature.

---

## 4. Data Sources

| Data | Source | Cost |
|---|---|---|
| Satellite orbital elements (TLEs) | [Celestrak](https://celestrak.org/) | Free |
| Space weather / geomagnetic activity | [NOAA Space Weather Prediction Center](https://www.swpc.noaa.gov/) | Free |

No paid data licensing required for MVP or Phase 2 — this is a meaningful part of why the project fits a lean budget.

---

## 5. Technical Approach

- **Platform:** iOS-first (AR overlay via ARKit favors native)
- **Stack:** Swift / SwiftUI + ARKit + Core Location
- **Orbit math:** [SatelliteKit](https://github.com/gavineadie/SatelliteKit) (SGP4/SDP4) via Swift Package Manager — see Project Status above for why
- **Backend:** None for now — TLE and space-weather data are fetched client-side. See "TLE delivery model" in Project Status for why this needs to change before real distribution.

### Layout

```
OverheadCore/            Pure Swift package — no UIKit/ARKit, testable with `swift test`
  Sources/OverheadCore/
    TrackedObject.swift       Satellite/station model + category enum (stations, starlink)
    CelestrakClient.swift     Fetches + parses TLEs from Celestrak's free GP feed
    SatellitePosition.swift   SGP4 propagation → observer-relative azimuth/elevation/range
    PassPredictor.swift       Brute-force rise/set search for pass notifications
  Tests/OverheadCoreTests/

Overhead/                 iOS app target (SwiftUI + ARKit)
  App/                        App entry point, ContentView, permission flow
  AR/                          ARSCNView wrapper placing billboarded labels by az/el
  Services/                   LocationService (CoreLocation), SatelliteTrackingService
  Views/                      InfoCardView (tap-for-details sheet)

project.yml                XcodeGen source of truth — regenerate the .xcodeproj after editing:
                            `xcodegen generate`
```

---

## 6. Budget

- Target build cost: **~$1,000**
- Achievable given zero data licensing costs and a scoped native AR MVP

---

## 7. Content Strategy Summary

| Feature | Content Role | Cadence |
|---|---|---|
| AR satellite tracker | **Lead/flagship** — the core viral hook | On-demand, filmable any clear evening |
| Aurora alerts | Companion/premium feature | Seasonal, opportunistic |
| Astrophotography planner | Post-audience utility play | Long-term, once trust is established |

**One app, two viral hooks, both powered by free data, both personally filmable with founder credibility as the differentiator.**

---

## 8. Open Questions / Next Steps

- [ ] Lock a real project name (this doc uses a placeholder)
- [x] Confirm SGP4/orbit propagation library choice — SatelliteKit (see Project Status)
- [x] Scope exact MVP object list — ISS + Starlink only (see Project Status)
- [ ] Define notification permission flow / pass-prediction UX (math exists in `PassPredictor`, no scheduling wired up yet)
- [ ] Decide whether this sits inside the existing app portfolio's shared design language or gets its own visual identity
- [ ] Build and run on a real device to verify the AR overlay actually looks right (unverified — see Project Status)
