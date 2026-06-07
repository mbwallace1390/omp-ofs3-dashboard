# ELRS and S.Port Setup Guide

This guide is based on the current runtime code in OFS3 for Ethos. The important detail is that protocol detection and channel mapping are hard-coded, so the dashboard expects specific channels for `crsf` and `sport`.

## How protocol detection works

There is no manual protocol selector in the widget. OFS3 auto-detects telemetry in this order:

1. `sport` on the internal module if FrSky telemetry root sensor `0xF101` exists.
2. `crsf` on the external module if CRSF link telemetry exists.
3. `sport` on the external module if FrSky telemetry root sensor `0xF101` exists.

Practical takeaway:

- If you want ELRS/CRSF mode, keep the internal RF module disabled unless you intentionally want the dashboard to use S.Port/F.Port.
- If both are active, internal `sport` wins before external `crsf` is even checked.

## Telemetry the dashboard expects

### ELRS / CRSF

The dashboard looks for native CRSF telemetry for:

- Link quality / RSSI
- Voltage
- Current
- Consumption
- ESC temperature
- RPM

It also creates derived telemetry sensors named `Armed`, `Profile`, and `Smart Fuel`.

Important ELRS / CRSF RPM note:

- On some radios the RPM sensor can initially come in with the wrong type or limits, often showing up as `GPSAlt`.
- If RPM looks wrong or never reaches realistic headspeed values, edit the RPM sensor in Ethos and increase its maximum value.
- This is especially important if the dashboard is not entering flight mode even though the model is armed and spinning.

### S.Port / F.Port

The dashboard looks for FrSky-style telemetry for:

- `RSSI`
- `ESC Voltage`
- `ESC current`
- `ESC temp`
- `ESC consumption`
- `RPM`

It also creates or updates derived telemetry sensors named `Armed`, `Profile`, and `Smart Fuel`.

If voltage/current/RPM data are missing, the related dashboard fields will stay blank. Flight timing and logging depend on valid arm state and RPM.

## Channel map used by OFS3

Channel numbers below are the normal radio channel numbers from the model setup page.

| Function | ELRS / CRSF | S.Port / F.Port | Notes |
| --- | --- | --- | --- |
| Aileron | CH1 | CH1 | Stored by runtime, not directly used by the dashboard today |
| Elevator | CH2 | CH2 | Stored by runtime, not directly used by the dashboard today |
| Collective | CH3 | CH6 | Stored by runtime, not directly used by the dashboard today |
| Rudder | CH4 | CH4 | Stored by runtime, not directly used by the dashboard today |
| Arm | CH5 | CH8 | Used to derive the `Armed` sensor |
| Throttle | CH6 | CH3 | Stored by runtime, not directly used by the dashboard today |
| Mode | CH7 | CH7 | Mapped, but not currently consumed by dashboard logic |
| Headspeed / Profile | CH8 | CH7 | Used to derive the `Profile` sensor |

Two channels matter most today:

- `Arm`
- `Headspeed / Profile`

Those are the channels that directly drive the dashboard's derived `Armed` and `Profile` sensors.

## How arm and profile are derived

### Armed

The dashboard treats the arm channel like this:

- Channel value `>= 500`: armed
- Channel value `< 500`: disarmed

Internally the derived telemetry sensor is:

- `0` when armed
- `1` when disarmed

That is why the arm switch needs to go properly high in the armed position.

### Profile

The dashboard treats the headspeed/profile channel like this:

- Below `-500`: Profile 1
- Between `-500` and `500`: Profile 2
- Above `500`: Profile 3

In practice this means a 3-position switch is the right choice for the profile channel.

## When OFS3 starts a flight

OFS3 does not start a flight just because the arm channel changes.

It switches to `inflight` only when both are true:

- The derived `Armed` sensor says armed
- RPM is above `1000`

It only increments the model flight count after `10` seconds in flight.

Practical takeaway:

- Arm alone is not enough
- RPM telemetry must be working
- A S.Port/F.Port dummy arm channel helps the dashboard know armed/disarmed state, but flight timing still depends on RPM too

## Recommended ELRS / CRSF setup

1. Use the external ELRS module for the model.
2. Disable internal RF unless you deliberately want S.Port/F.Port to be selected instead.
3. Discover telemetry and confirm CRSF values are present for link, voltage, current, consumption, temperature, and RPM.
4. If the RPM sensor appears as `GPSAlt` or has a very low maximum, edit that sensor in Ethos and raise the maximum value so normal headspeed can be displayed.
5. Put your arm switch on `CH5`.
6. Put your 3-position headspeed/profile switch on `CH8`.
7. If you also use a separate flight mode switch, `CH7` is the runtime's mapped mode channel, but the current dashboard profile logic reads `CH8`, not `CH7`.

## Recommended S.Port / F.Port setup

1. Discover telemetry and confirm `RSSI`, `RPM`, `ESC Voltage`, `ESC current`, `ESC temp`, and `ESC consumption` are present.
2. Create a dummy output on `CH8` that mirrors the heli/radio arm state.
3. Put your 3-position headspeed/profile switch on `CH7` if you want profile display and profile voice events to follow it.
4. Be aware that the hard-coded S.Port runtime map assumes `Collective = CH6` and `Throttle = CH3`.

Notes for S.Port/F.Port:

- `CH8` is the important arm mirror channel.
- `CH7` is the profile channel the dashboard actually uses.
- `CH5` is not used by the current dashboard logic in S.Port mode.

## Quick checks on the radio

After the widget has run once, you should be able to verify these derived sensors:

- `Armed`
- `Profile`
- `Smart Fuel`

Useful sanity checks:

- Flip the arm switch and confirm `Armed` changes between `1` and `0`.
- Move the profile switch and confirm `Profile` changes between `1`, `2`, and `3`.
- Spin the head and confirm RPM rises above `1000` when the model is actually flying.

## Troubleshooting

### Dashboard stuck on "Telemetry waiting"

- Telemetry root source was not detected.
- Re-discover sensors in Ethos.
- Check whether the correct RF module is enabled.
- Remember that internal `sport` is checked before external `crsf`.

### Arm/disarm voice or state is wrong

- Verify the arm function is on the correct channel for the active protocol.
- Verify the armed position drives the channel above `500`.
- On S.Port/F.Port, confirm the dummy `CH8` output really follows arm state.

### Profile always shows 2

- The profile channel is on the wrong output, or
- The switch travel is not reaching below `-500` and above `500`

### Flights are not being counted

- Confirm arm state is changing correctly
- Confirm RPM telemetry is working
- If ELRS / CRSF RPM came in as `GPSAlt`, edit the sensor and increase its maximum value
- Confirm RPM exceeds `1000`
- Confirm the flight lasts more than `10` seconds

### ELRS model is being treated like S.Port

- Internal `sport` telemetry was probably found first.
- Disable the internal RF module for that model and try again.
