# Current

A native UIKit battery instrument for iPhone and iPad running iOS 26 or later. No SwiftUI, third-party dependencies, backend, analytics, or network access.

## Run

1. Open `Current.xcodeproj` in Xcode 26 or later.
2. For a physical device, select the **Current** target → **Signing & Capabilities**, leave **Automatically manage signing** enabled, and choose your **Team**. Add your Apple account in Xcode Settings → Accounts if needed.
3. Select the **Current** scheme, choose your device or a simulator, and Run. A simulator does not require a signing team.

To run tests on a physical device, also choose a team for **CurrentTests** and **CurrentUITests** under each target's **Signing & Capabilities**.

The app uses `com.joeli.current`. Test targets append `.tests` and `.uitests`. If these identifiers are unavailable to your team, choose a unique app identifier and update the matching test identifiers in Xcode. Keep your identifiers unchanged after registration with your team. Changing the app's bundle identifier creates a separate app identity; existing on-device sessions are not migrated automatically. Export any history you want to retain before switching identifiers.

Signing uses ordinary Xcode project settings, with no team preselected. No setup helper or separate signing configuration file is required. Xcode saves your team as `DEVELOPMENT_TEAM` in `Current.xcodeproj/project.pbxproj` and may also write `DevelopmentTeam` in its target metadata. The scheme chooses targets and build configurations; it does not store the signing team.

**Team selections modify a tracked project file.** They are not automatically Git-ignored. Leave personal signing changes out of commits; keep the project file itself tracked so legitimate target and build-setting changes can still be shared.

The app always uses real readings. There is no demo mode, simulated provider, or generated history. The simulator shows unavailable hardware measurements instead of reading the Mac's sensors. Legacy demo preferences/launch arguments cannot re-enable simulation, and legacy demo sessions are excluded when loading history.

Settings → Appearance offers **Auto**, **Dark**, and **Light**. Auto follows iOS, while Dark and Light stay fixed. The choice is saved across launches, applies to all app windows (including settings, sheets and charts), and does not restart monitoring or recording.

Debug builds still support temporary `--light` / `--dark` launch overrides. These do not overwrite the saved preference; choosing an appearance in Settings does.

## What It Measures

- Current USB input estimate, sampled peak, time-weighted session average, and rolling five-minute average.
- A scrubbable five-minute or full-session power chart.
- Observed energy input in Wh, battery percentage-point change, elapsed observation time, and valid-power coverage.
- USB input voltage/current, battery-sensor temperature, reported adapter rating, Low Power Mode, and system thermal state.
- The Health tab focuses on battery temperature, USB electrical readings and system status. Unsupported capacity and cycle-count fields are not displayed.
- Up to 30 saved device sessions, session details, individual deletion, bulk deletion with confirmation, and JSON export through the system share sheet.
- Field-by-field provenance and provider diagnostics.

Every hardware field is optional. Missing readings display as unavailable, never as invented device data.

## Important Device Limits

**Private sensor mappings are reverse-engineered and model/OS-dependent.**

`BatterySensorReader.m` replaces the permission-filtered battery-registry reader. It dynamically resolves the read-only IOHID event APIs and keeps **one client for the process lifetime**, including across foreground transitions and data-source toggles. Calls run on a worker queue and are serialized. Every poll rediscovers the power and temperature services, so it does not retain disconnected charger services.

Only these identified sensors are read:

| Sensor | Usage page / usage | Meaning |
| --- | --- | --- |
| `Charger VQ0u` | `0xff08` / `3` | USB input voltage, V |
| `Charger IQ0u` | `0xff08` / `2` | USB input current, A |
| `gas gauge battery` | `0xff00` / `5` | Battery temperature, °C |

The sensor API was observed in a developer-signed app on a physical iPhone: voltage/current values changed between polls, and gas-gauge sensors returned battery temperature. These mappings are not Apple-documented calibration guarantees and may be missing or mean something different on other devices.

`IOPSCopyExternalPowerAdapterDetails` separately supplies the reported adapter rating and wired/wireless flag. USB power requires a confirmed wired connection, one unambiguous voltage/current pair, matching usage codes, finite/plausible values, and a poll taking no longer than two seconds. Missing events, NaN, invalid values, duplicate USB names, slow polls, and disconnects leave a gap rather than inventing watts. Multiple gas-gauge temperatures are combined by their median only when the valid readings agree within 1 °C. Unknown sensor names are ignored.

`UIDevice.batteryState` remains authoritative. USB input can be positive even when the battery is full or charging is on hold because the phone itself consumes power. Low or zero input never causes an inferred **Charging paused** state. Wireless input and net battery intake are not calculated from the USB sensors.

**Source diagnostics** shows known sensor values, reader status, poll duration, and field provenance. Exports include these safe diagnostics, not raw service dictionaries, device identifiers, or serials. IOHID does not expose capacity or cycle count; temperature does not imply a battery-health percentage.

The reader does not observe keyboard/touch input, load Powerlog, read the old battery registry, change charging limits, invoke shell commands, bypass the sandbox, or alter system protections. No third-party runtime library or private entitlement has been added.

The public fallback uses `UIDevice` for battery level/state and `ProcessInfo` for thermal state and Low Power Mode.

The hardware-reader entry point is **disabled at compile time in the simulator**. A simulator process can otherwise see host-computer sensors or adapter data, which must never be represented as an iPhone battery.

This private-API target is for development/research and is not suitable for App Store submission. Turning off the runtime toggle does not remove private-API code from the binary.

A successful simulator test verifies the app, parser, and calculations, not access to a physical iPhone's sensors.

## Measurement Definitions

New charging sessions use USB input:

```text
USB input W         = USB sensor voltage V * USB sensor current A
interval energy Ws  = (previous input + next input) / 2 * interval seconds
average W           = sum(valid interval energy Ws) / sum(valid interval seconds)
energy Wh           = sum(valid interval energy Ws) / 3600
```

USB input includes power used by the phone and is neither net battery intake nor wall power. Adapter rating is shown separately and is never substituted for a missing voltage/current measurement. No efficiency factor is assumed to convert USB input to stored battery energy.

New sessions explicitly save `powerMeasurement: "usbInput"`. Version 1 sessions without that field retain their original **battery-intake** meaning in history, charts and exports. The recorder starts a separate session if the measurement basis changes; USB input and battery intake are never averaged together. Archive/export format 2 preserves old sessions without relabeling them. The storage filename stays unchanged so existing history is found.

Sampling is every two seconds, but the OS/driver may refresh the underlying values more slowly. The peak is a **sampled peak**, not a guaranteed physical peak.

The five-minute window clips and linearly interpolates valid interval boundaries. Missing/nonfinite readings, reversed timestamps, and gaps longer than ten seconds do not contribute energy. One reading can establish a sampled peak, but cannot establish a time-weighted average or energy. Measured zero and unavailable data remain distinct.

## Chart Interaction and Rendering

Vertical drags starting on the curve scroll the page; horizontal drags scrub readings. The directional filter belongs to the chart's own gesture delegate, not `UIView.gestureRecognizerShouldBegin`, whose scope also includes ancestor scroll gestures.

Both chart windows have cached geometry. Long curves retain each screen column's endpoints, minimum and maximum, with missing-data gaps kept separate. Scrubbing, statistics and exports use the original samples, not the reduced drawing.

Curve and cursor use separate shape layers. Segment switches reuse prepared paths and cached statistics instead of rescanning the session or cross-fading the entire chart. The native Liquid Glass segmented control remains unchanged.

## Session Lifecycle

A session is a **foreground observation**, not a claim to have observed an entire cable connection.

- Recording begins when connected power is first observed.
- A connected but paused or full battery remains in the same observation.
- Disconnecting, entering the background, locking, changing provider, or losing observation ends it at the last recorded sample.
- Returning while connected starts a new observation. An unobserved unplug/replug is never silently merged into history.
- An unfinished archive recovered after termination is closed as interrupted.
- Continuous observations are split after eight hours to bound memory and storage.

**Keep screen on** disables auto-lock only while connected and actively monitored. It is off by default, changes the phone's power consumption, and cannot override a manual lock or background execution limits. No fake background modes or background polling promises are used.

Session JSON is written atomically into Application Support, protected until first unlock, and excluded from backups. It is checkpointed every 30 seconds and synchronously flushed on backgrounding. Abrupt termination can lose readings since the last checkpoint. An unreadable archive is preserved and reported instead of silently overwritten.

Exports contain interpreted measurements and provenance, not raw registry dictionaries, serial numbers, or device identifiers. The legacy `isDemo` archive field remains for compatibility and is always false in new recordings.

## Structure

```text
Current/
  App/          UIKit application, scene lifecycle, native glass tab/navigation bars
  Core/         Typed snapshots, IOHID validation, measurement basis, recorder, statistics
  Telemetry/    Read-only Objective-C IOHID reader, foreground monitor, persistence
  UI/           Adaptive components, animated gauge, cached chart geometry/layers, appearance
  Screens/      Charging, health, history, session detail, settings, diagnostics
  Resources/    App icon, adaptive colors, privacy manifest
CurrentTests/   Sensors, calculations, archive migration, chart geometry, gesture and rendering regressions
CurrentUITests/ Navigation, scrolling/scrubbing, segment performance, settings, export, appearance, text size
Scripts/       Reproducible app-icon renderer using original vector artwork
```

Liquid Glass uses real `UIGlassEffect`, native glass button configurations, and the iOS 26 tab/navigation bars. The app supports system light/dark appearance, Dynamic Type, VoiceOver chart adjustment, Reduce Motion, haptic chart selection, and accessible settings.

## Development Checks

Choose a simulator installed on your Mac:

```sh
xcrun simctl list devices available
swiftformat Current CurrentTests CurrentUITests Scripts
swiftlint lint --strict
xcodebuild -project Current.xcodeproj -scheme Current \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

UI tests attach screenshots to the Xcode test result. `Scripts/GenerateAppIcon.swift` regenerates the included 1024px icon.

## Public Repository Hygiene

Commit source files, shared project settings, and synthetic tests only. Real-device captures, downloaded app containers, session exports, logs, build outputs, Xcode user state, and credentials are excluded by `.gitignore`. Ignore rules do not remove already tracked files. Team selections made in Xcode are tracked changes to `project.pbxproj`, not ignored user state; review and exclude personal signing changes before committing.

Review the staged files before committing. Publish the Git repository, not a ZIP of the working directory: ignored local files may still contain personal data. Commit author and committer names and emails are public metadata; use an identity you intend to publish.

The repository contains no recorded device sessions. Test fixtures are generated in code. The app icon is original vector artwork; SF Symbols are used only within the app's interface.

## Attribution

The IOHID approach and sensor mappings were informed by Greg Wilson's MIT-licensed **ios-charging-monitor**. Its notice is retained in `THIRD_PARTY_NOTICES.md`; no third-party runtime library is bundled. This upstream notice does not select a license for the rest of this repository.

## API References

Primary references used for the API boundary and units:

- Apple UIKit: `https://developer.apple.com/documentation/uikit/uiglasseffect`
- Apple UIDevice: `https://developer.apple.com/documentation/uikit/uidevice/batterylevel`
- Apple power-source/adapter API: `https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSources.c`
- IOHID approach and sensor-map reference, Greg Wilson's ios-charging-monitor (MIT): `https://github.com/gregsramblings/ios-charging-monitor/blob/main/ChargeSpeed/HIDSensors.swift`
- Additional mapping cautions: `https://github.com/ResistanceTo/MiniWatts`
- Apple App Review Guidelines, section 2.5.1: `https://developer.apple.com/app-store/review/guidelines/`
