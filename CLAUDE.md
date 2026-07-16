# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OFS3 for Ethos is a Lua widget/tool for FrSky Ethos (running on Ethos-compatible radios). It is a port of the core parts of the Rotorflight dashboard, adapted to support ELRS (CRSF) and S.Port/F.Port telemetry without Rotorflight's MSP link — telemetry-only, "OFS3" (ELRS mode). All application code lives under `src/ofs3/`, which is the exact tree that gets deployed to a radio's `SCRIPTS:/ofs3/` (or `SCRIPTS:/<preferences>/`) directory.

## Build / package / deploy

There is no compiled build for the Lua code itself — it runs as-is on the radio or in the Ethos Simulator. Tooling exists for packaging and pushing to a radio:

- **CI packaging** (what actually ships): `python .github/scripts/build_locale_package.py --lang <en|de|es|fr|it|nl> --version <ver> --artifact <out.zip>`
  - Stages `src/ofs3` into `build/<lang>/scripts/ofs3`, builds the locale's i18n JSON bundle via `bin/i18n/build-single-json.py`, resolves `@i18n(...)` tags in-place via `.vscode/scripts/resolve_i18n_tags.py`, copies the matching soundpack from `bin/sound-generator/soundpack/<lang>` (falls back to `en`), stamps the version suffix into `main.lua`, then zips it.
  - PR/push/tag workflows (`.github/workflows/{pr,push,testing,release}.yml`) all call this script per-locale; there is no separate lint/test CI job.
- **Local dev deploy** (Windows + VS Code + Ethos extension, see `.vscode/tasks.json` and `.vscode/scripts/deploy.py`): tasks like "Deploy & Launch [SIM]" and "Deploy Radio" run `deploy.py` with `--step i18n --step soundpack --step sensors` to stage i18n/soundpack/sensor config and either launch the Ethos Simulator or push over USB serial (`connect.py`, config in `.vscode/deploy.json`) to a physical radio.
- **Lua formatting**: `bin/format_lua.py` strips comments, runs `lua-format` (must be on PATH) with fixed style flags, and re-injects a compact GPLv3 header. Run as `python bin/format_lua.py [root] [--dry-run] [--backup]`. Only apply this deliberately (e.g. on request) — it rewrites every `.lua` file under the given root and strips existing comments.
- **i18n**: source strings live per-key across `bin/i18n/json/<lang>.json` (raw editor form) and `scripts/ofs3/i18n/<lang>.json` (build form used by `build-single-json.py`). Widget/theme Lua files reference strings via `@i18n(key)`-style tags that `resolve_i18n_tags.py` substitutes at package time — don't expect these tags to resolve when reading source directly.

No package.json/npm, no unit test suite — verification is done by running in the Ethos Simulator or on hardware.

## Architecture

### Module loading (`src/ofs3/main.lua`)
`main.lua` defines a single global-ish table `ofs3` (stored in `package.loaded.ofs3`, retrieved elsewhere via `require("ofs3")`) holding shared state: `ofs3.session`, `ofs3.widgets`, `ofs3.tools`, `ofs3.theme`, `ofs3.flightmode`, `ofs3.preferences`, `ofs3.config`. Everything else is lazy-loaded on first use via `loadfile(...)(...)` calls guarded by `ensureSharedModules()` / `ensureWidgetModules()` / `ensureLogsTool()` — this keeps RAM/flash usage down on the radio, so avoid `require`-ing heavy modules eagerly; follow the existing `assert(loadfile(path))(config)` pattern instead.

`main.lua` registers exactly two Ethos integration points via `system.registerWidget` (the dashboard widget, key `ofs3dsh`) and `system.registerSystemTool` (the "OFS3 Logs" tool). Both dispatch into lazily-loaded modules through small wrapper closures (`callWidget`, `callWidgetConfigure`, `callLogsTool`).

### Shared libs (`src/ofs3/lib/`)
- `ini.lua` — INI-style config file read/write (model/user preferences persistence).
- `utils.lua` — cross-cutting helpers: logging, rounding, image/bitmap loading with path-candidate + cache logic, sound playback path resolution (user override → locale → default), simulator sensor injection (`sim/sensors/*.lua`), and `ofs3.session` initialization (arm/connection state, timers, rx channel map).
- `telemetry.lua` — protocol auto-detection (`crsf` vs `sport`) and telemetry sensor discovery/mapping; see `docs/protocol-setup.md` for the exact detection order and channel maps this drives.
- `sensors.lua` — derives synthetic/computed sensors (e.g. `Armed`, `Profile`) from raw channel/telemetry values, per the CH5/CH8 (CRSF) vs CH8/CH7 (S.Port) mapping documented in `docs/protocol-setup.md`.
- `smartfuel.lua` — derived "Smart Fuel" estimation logic.
- `runtime.lua` — per-frame runtime state machine: flight mode transitions (`preflight` → `inflight` → `postflight`), arm/RPM-gated flight detection, flight counting/timers.
- `events.lua` — voice/alert event triggers (armed, voltage, profile, etc.), gated by `ofs3.preferences.events`.
- `logs.lua` — flight CSV logging (written during `inflight` state) into the logs directory read by the logs tool.

### Dashboard widget (`src/ofs3/widgets/dashboard/`)
- `dashboard.lua` / `configure.lua` — the widget's Ethos lifecycle handlers (`create`, `paint`, `event`, `wakeup`, `menu`, `read`/`write` for persisted config) and its configuration UI.
- `lib/themes.lua` — theme discovery: scans `widgets/dashboard/themes/<@themeid>/` for an `init.lua` describing `preflight.lua` / `inflight.lua` / `postflight.lua` layout files; falls back to `@rt-rc` if none found. Theme IDs are directory names prefixed with `@` (see `themes/@aegis`, `themes/@rt-rc`).
- `lib/wrapper_factory.lua` — `factory.createObjectWrapper(objectType, defaultSubtype)` builds the shared `paint`/`wakeup`/`dirty` wrapper used by every dashboard object category (dial, gauge, text, image, time, navigation, func). Each object type lazily loads its subtype renderer from `objects/<type>/<subtype>.lua` on first use and caches it in `ofs3.widgets.dashboard.renders`. **New object subtypes should follow this same lazy-load-and-cache convention rather than requiring themselves eagerly.**
- `objects/` — one folder per object category (`dial`, `gauge`, `text`, `image`, `time`, `navigation`, `func`), each with subtype implementations (e.g. `gauge/arc.lua`, `gauge/bar.lua`, `text/craftname.lua`). **`docs/dashboard-objects.md` is the authoritative field reference for every object's config keys (title/value/padding/threshold options etc.) — consult and update it when changing an object's parameters.**
- `lib/loaders.lua`, `lib/utils.lua`, `lib/logviewer.lua`, `lib/toolbar.lua` — shared widget-layer helpers, box-cache/model-prefs-readiness helpers (`utils.isModelPrefsReady`, `utils.resetBoxCache`), and the in-widget log viewer UI.
- `themes/@<id>/` — theme packages; each has `init.lua` (metadata: name, standalone flag, per-flightmode layout filenames) plus the `preflight.lua`/`inflight.lua`/`postflight.lua` layout definitions themselves.

### Logs tool (`src/ofs3/tools/logs.lua`)
Standalone system tool (independent of the dashboard widget) for browsing/managing recorded flight logs; registered separately in `main.lua` and shares `ofs3.logs`/`ofs3.tools.logs` state.

### Protocol / channel behavior
Telemetry protocol detection and RX channel mapping are **hard-coded**, not user-configurable in the UI. Before changing anything in `telemetry.lua`, `sensors.lua`, or `runtime.lua` related to arm/profile/flight detection, read `docs/protocol-setup.md` — it documents the exact detection order (internal sport → external crsf → external sport), the CRSF vs S.Port channel maps, the arm threshold (`>= 500`), profile thresholds (`< -500` / `-500..500` / `> 500`), and the flight-start gate (armed AND RPM > 1000, counted after 10s).

## Conventions

- Every `.lua` file carries a short GPLv3 header comment block (see `bin/format_lua.py`'s `make_header`); preserve it when editing, and rely on the formatter (not hand-editing) to regenerate it if asked to reformat.
- Asset/path resolution throughout the codebase tries multiple candidate paths in order (raw path → `SCRIPTS:/...` → `BITMAPS:/...` → extension swap `.png`/`.bmp`) and caches the winning path — follow this pattern (see `utils.loadImage`, `utils.playFile`) rather than assuming a single fixed path.
- Widget object config tables are large, mostly-optional flat option bags (title*, value*, padding*, threshold, color, transform, unit fields) rather than nested structs — match this shape when adding new object parameters, and document new keys in `docs/dashboard-objects.md`.
