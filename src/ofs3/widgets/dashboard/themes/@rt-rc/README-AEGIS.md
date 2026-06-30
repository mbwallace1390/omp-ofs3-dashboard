# Aegis OFS3 Theme

First radio-testable Aegis port for the OMP OFS3 Dashboard.

## Target

- FrSky Ethos color radios, designed around the X20 Pro
- Compact X20 Pro widget zone: 784x294
- Full-width dashboard zones supported by the existing OFS3 dashboard engine
- OMP OFS3 telemetry over CRSF or S.Port/F.Port
- Existing OFS3 preflight, inflight and postflight state machine

## Telemetry used

- RPM
- ESC temperature
- Pack voltage
- Current
- Consumption
- Smart Fuel
- RSSI/link quality
- Derived Armed state
- Derived Profile
- Radio throttle channel

The port intentionally does not display BEC voltage, governor state, separate PID/rate profiles, arm-disable reasons or altitude because the current OFS3 telemetry table does not expose verified sources for them.

## Current behavior

This test branch replaces the active `@rt-rc` screen modules with Aegis while leaving the dashboard engine, protocol detection and logging system unchanged. The stock theme remains available on the repository's `main` branch.

The screens switch to a compact layout whenever the widget height is below 360 pixels. Compact mode reduces the center graphics, derives row spacing from each card's actual height and simplifies small telemetry cards so text cannot overlap at 784x294.

## Defaults

- Maximum headspeed: 2500 rpm
- ESC warning: 110 C
- ESC maximum: 150 C
- Smart Fuel warning: 25 percent
- Link warning: 50 percent

The shared module already reads optional values from a future `[system/aegis]` model-preference section, so a settings UI can be added after the first radio test without restructuring the theme.
