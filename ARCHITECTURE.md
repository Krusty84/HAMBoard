# HAMBoard Architecture

## Overview

HAMBoard is a SwiftUI-first tvOS app focused on amateur radio operations. It combines:

- live DX Cluster spot streaming over Telnet,
- near-real-time propagation/solar data,
- contest calendar browsing,
- operator configuration and diagnostics.

The app is organized as a tabbed shell (`MainWindow`) with feature-specific views and state owners, plus shared helpers for parsing, network transport, QR generation, and country/prefix resolution.

## Top-Level Structure

```text
HAMBoard/
├── HAMBoardApp.swift                  # App entry point and app lifecycle hooks
├── MainWindow.swift                   # Root tab shell + global overlays
├── API/
│   └── DXClusterTelnetConnector.swift # Telnet transport, handshake, negotiation
├── Helpers/
│   ├── DXCluster/                     # Spot models/parser/config/DXCC/country mapping
│   ├── Propagation/                   # SVG map loader
│   ├── QRCodeCache.swift              # Shared async QR cache
│   └── QRCodeGenerator.swift          # QR generation utility
└── Views/
    ├── DXCluster/                     # Live spots + announcements UI
    ├── DXStatistics/                  # Top bands/countries overlay
    ├── Propagation/                   # Solar + map pages
    ├── Contests/                      # RSS-fed contest list + QR detail
    ├── Settings/                      # General, cluster config, debug, about
    ├── Clock/                         # UTC/local clock overlay
    └── About/                         # Credits + repo QR panel
```

## Runtime Composition

1. `HAMBoardApp` starts the app and hosts `MainWindow`.
2. `MainWindow` owns:
- current tab selection,
- one active `DXClusterTabViewModel` session,
- shared `DXStatViewModel` for top-band/top-country overlays.
3. When cluster host/port/callsign changes in `@AppStorage`, `MainWindow` rebuilds the cluster view model and reconnects.
4. Incoming spots are pushed into both:
- DX spot UI feed (`DXClusterTabViewModel.spots`)
- rolling statistics actor (`DXStatViewModel.ingest(spots:)`)

## Core Data Flow: DX Cluster

### 1) Transport Layer

`DXClusterTelnetConnector` (`API/`) handles:

- TCP connection with `Network` (`NWConnection`)
- TELNET control byte parsing and negotiation replies
- login prompt detection and callsign submission
- cluster flavor detection (DXSpider / AR-Cluster / CC / unknown)
- startup command bootstrap (`set/dx`, `set/wwv`, etc.)
- event emission to upper layers

### 2) Parsing Layer

`DXClusterParser` converts raw text lines into:

- `.spot(Spot)`
- `.wwv(String)`
- `.comment(String)`
- `.unknown(String)`

`Spot` includes resolved station metadata (`Station`) and derived fields (band, mode, time token normalization).

### 3) Resolution Layer

- `Station` resolves prefixes against `DXCCDatabase` (`cty.plist`).
- `CountryMapper` maps DXCC country names to ISO codes/display names using `country_code.json`.

### 4) Presentation Layer

`DXClusterTabViewModel`:

- maintains bounded in-memory feeds (`spots`, `announcements`)
- tracks connection and loading state
- performs periodic announcement polling commands
- exposes filtered spot list by `BandFilter`

`DXClusterTabView` renders spots and announcements with tvOS-friendly segmented paging.

## Other Feature Modules

### Propagation

- `PropagationTabView` provides page switching between:
  - `SolarConditionsView`
  - MUF SVG map
  - foF2 SVG map
- `SolarConditionsViewModel` periodically fetches and parses `https://www.hamqsl.com/solarxml.php`.
- `PropagationMapSVGLoader` loads remote SVG maps via `SVGKit`.

### Contests

- `ContestsTabViewModel` fetches RSS from `https://www.contestcalendar.com/calendar.rss`.
- XML is parsed by `ContestCalendarRSSParser`.
- Selected contest link is converted to QR via `QRCodeCache`.

### Settings

`SettingsTabViewModel` is the persistence hub for:

- callsign and display settings
- selected cluster host
- custom cluster endpoints
- removed defaults
- per-host port overrides

All are persisted via `@AppStorage` with JSON-encoded data where needed.

### Debug

`DXClusterDebugViewModel` opens a dedicated connector for raw stream inspection and live troubleshooting.

## Shared Services

- `QRCodeGenerator`: CoreImage QR generation
- `QRCodeCache`: async cached QR preload/retrieval
- `DXStatViewModel` + `DXStatStatActor`: rolling-window aggregation for overlay metrics

## State Management Pattern

The current codebase uses a mixed strategy:

- `ObservableObject` + `@Published` for legacy/main feature view models.
- `@Observable` (Observation framework) in newer models (for example contests and debug view models).
- `@AppStorage` for user settings and cluster configuration persistence.

## External Dependencies

- `FlagKit` for country flags in spot rows.
- `SVGKit` for rendering propagation SVG maps.


## Testing

Current test coverage includes:

- `DXClusterParserTests`: spot/comment/WWV parsing behavior.
- `DXClusterTelnetConnectorTests`: integration-style tests with a local telnet server fixture (login, startup commands, chunked payload parsing, TELNET negotiation).

