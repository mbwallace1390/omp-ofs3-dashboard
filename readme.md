**OFS3 FOR ETHOS**

OFS3 for ethos is a port of the core parts of rotorflight dashboard to support OFS3 on ethos - running ELRS mode.

<img src="https://github.com/robthomson/omp-ofs3-dashboard/blob/main/.github/gfx/dash.png?raw=true" width="800" alt="MAIN PAGE">

<img src="https://github.com/robthomson/omp-ofs3-dashboard/blob/main/.github/gfx/logs.png?raw=true" width="800" alt="LOGS">



## Setup guide

The dashboard auto-detects `crsf` and `sport`, and it uses different hard-coded channel maps for each protocol.

See the full guide here:

- [ELRS and S.Port setup guide](docs/protocol-setup.md)

Quick notes:

- ELRS / CRSF: arm is read from `CH5`, profile/headspeed from `CH8`
- S.Port / F.Port: create a dummy arm mirror on `CH8`, and use `CH7` for profile/headspeed
- Flight timing/logging needs valid arm state and RPM above `1000`

-----
Like what you see.  Consider donating..

[![Donate](https://github.com/robthomson/RF2STATUS/blob/main/git/paypal-donate-button.png?raw=true)](https://www.paypal.com/donate/?hosted_button_id=SJVE2326X5R7A)
