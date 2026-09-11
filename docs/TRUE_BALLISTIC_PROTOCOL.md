# FX True Ballistic Chronograph — BLE protocol

> Derived from the device firmware and the vendor's reference clients. Not an
> official specification. Reproduced here so that anyone can talk to the
> device from their own software. Field layouts are what the firmware writes
> today and may change in future firmware.

The True Ballistic Chronograph (TBC) is a 24.08 GHz Doppler radar. Unlike the
Pocket Chronograph, which broadcasts shots in its advertisement, the TBC is a
**connected GATT device**: you connect, subscribe to a characteristic, and get
one notification per shot.

Chrono Lite implements everything in this document except the remote
configuration channel. The implementation lives in
`lib/services/true_ballistic_client.dart` and is meant to double as a worked
example; the tests in `test/true_ballistic_parser_test.dart` contain byte-level
vectors for every packet.

---

## 1. Finding the device

The TBC does **not** advertise its data service, so scan on name.

| Property | Value |
|---|---|
| Advertised name | starts with `vXfS3c6k` |
| Data service | `00001623-88ec-688c-644b-3fa706c0bb76` |

The name is an obfuscated vendor fingerprint, not a typo. Match on the
prefix; the full name may carry a suffix.

## 2. Characteristics

All in the data service above.

| UUID (short) | Name | Properties | Purpose |
|---|---|---|---|
| `0x1624` | Shot | read, notify, ≤20 bytes | One binary packet per shot. **This is the one you want.** |
| `0x1625` | Cmd | read, write, 2 bytes | Declared, but nothing in the firmware reads it. |
| `0x1626` | Stream | read, ≤20 bytes | Raw Doppler stream. Very chatty; ignore. |
| `0x1627` | Battery | read, 1 byte | Percentage 0–100. Not notifiable, read it once. |
| `0x162B` | 3rd party | read, notify, ≤20 bytes | ASCII downrange velocities. Newer firmware only. |

Full UUIDs follow the pattern `0000162X-88ec-688c-644b-3fa706c0bb76`.

Subscribe to `0x1624` (and optionally `0x162B`) **before** enabling
notifications, so a shot fired right after the CCCD write is not lost.

## 3. Shot notification (`0x1624`)

Byte 0 is a packet type. Two types are emitted, chosen by whether the
on-device ballistic-coefficient solver converged for that shot.

### 3.1 Type `0x0B` — ballistic (BC fit succeeded)

| Bytes | Field | Encoding |
|---|---|---|
| 0 | type | `0x0B` |
| 1–3 | muzzle Doppler | uint24 big-endian, Hz at a 24.08 GHz carrier |
| 4–7 | BC | float32 big-endian, in the units of the drag model |
| 8 | drag model | see table below |

Drag model ids match the device menu:

| Id | Model |
|---|---|
| 0 | Basic (never appears in `0x0B`, see 3.3) |
| 1, 2 | G1 / G7 first-generation tables, no longer selectable |
| 3 | G1 |
| 4 | G7 |
| 5 | RA4 (rimfire) |
| 6 | GA (airgun) |

The BC is measured **near the muzzle**. It can legitimately differ from the
number printed on the ammunition box, which is often quoted at a lower
velocity. Average several shots before trusting it.

### 3.2 Type `0x0C` — polynomial (BC fit failed or Basic mode)

| Bytes | Field | Encoding |
|---|---|---|
| 0 | type | `0x0C` |
| 1–3 | muzzle Doppler | uint24 big-endian, as above |
| 4–7 | coef 0 | float32 big-endian |
| 8–11 | coef 1 | float32 big-endian |
| 12–15 | coef 2 | float32 big-endian |
| 16 | TX offset | MHz above 24 024 MHz |
| 17–18 | sampling freq | uint16 big-endian, kHz |

The coefficients describe the velocity decay `v(t) = c0 + c1·t + c2·t²` in
Doppler Hz against a sample index, where one index step is
`1024 / (sampling_kHz × 1000)` seconds. Chrono Lite parses past these and
uses only the muzzle value.

### 3.3 Which type will I get?

* Drag model **Basic** → always `0x0C`. The solver never runs.
* G1 / G7 / RA4 / GA → `0x0B` when the solver converged (within 0.5 m/s
  after at most 30 iterations), otherwise `0x0C`.

So `0x0C` means "no BC for this shot", **not** "the user picked Basic".
A G1 unit will send some shots as `0x0C` and that is
normal.

### 3.4 Converting Doppler Hz to velocity

The straightforward form:

```
v_ms = raw × 299 792 458 / (2 × 24 080 000 000)
```

The vendor apps use a two-step form inherited from the older 10.525 GHz
Pocket radar, and truncate in between:

```
hz   = trunc(raw × 10525 / 24080)
v_ms = hz × 299 792 458 / 10 525 000 000 / 2
```

The two agree to within 0.015 m/s. Chrono Lite uses the second so its
numbers match the FX apps to the last digit. A raw value of 0 is the device's
idle frame, not a shot.

Worked example: raw `0x02 0x34 0xC7` = 144583 → 63195 Hz → 900.02 m/s →
2952.8 fps.

## 4. 3rd party interface (`0x162B`)

Newer firmware adds a plain-text characteristic so integrators can get
downrange velocities without re-fitting the `0x0C` polynomial. It fires right
after the `0x1624` packet for the same shot.

* Payload is ASCII, format `%05u-%05u-%05u`, 17 characters.
* Fields are velocity at **0 m, 50 m and 100 m**, in **tenths of fps**,
  zero-padded to five digits. Distances are fixed in firmware and do not
  follow the device's display-distance settings.
* Before the first shot the value reads `Boot`.
* The 50 m and 100 m fields are `00000` whenever the BC fit failed (the same
  shots that arrive as `0x0C`).
* When a stored shot is replayed from the device menu only the first field is
  filled.

Example: `20434-20441-20623` → 2043.4 / 2044.1 / 2062.3 fps.

Note that the 0 m field is the regression's extrapolated muzzle velocity and
can differ by a few fps from the Doppler peak in the `0x1624` packet for the
same shot.

## 5. Remote configuration

The device can be configured over Bluetooth, but **not** through the data
service. The BLE module is an Adafruit Bluefruit, and while the device is
idle on its velocity screen the firmware puts the module into UART bridge
mode. Lines you write to the **Nordic UART Service** land in the device's
command parser, and replies come back the same way.

| UUID | Role |
|---|---|
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | Nordic UART Service |
| `6E400002-…` | RX — write your line here |
| `6E400003-…` | TX — subscribe for replies |

The bridge is only open while the radar is **idle**. As soon as measuring
starts the module is switched back to command mode and lines are ignored.

### 5.1 Queries

Send `$` + two letters. Reply is `$…!`.

| Send | Reply |
|---|---|
| `$FW` | `$<firmware version>!` |
| `$CF` | `#V1=…,V2=…,…,HU=…!` — the full current configuration |
| `$TU` `$TE` `$PR` `$HU` | `$TU=n!` etc. — single weather values |

### 5.2 Setting values

Send `#KEY=int,KEY=int,…!`. A `#` inside the line also works as a separator.
All values are integers. One unknown key rejects the **whole** line.

| Key | Setting |
|---|---|
| `V1`, `V2` | primary / secondary velocity unit |
| `VR` | velocity range |
| `BO` | velocity offset |
| `WU`, `BW` | weight unit, bullet weight |
| `DU`, `D0`…`D3` | distance unit, the four display distances |
| `DM` | drag model (ids as in §3.1) |
| `ST` | auto shutdown time |
| `PO` | radar power output |
| `TS` | trigger sensitivity |
| `NI` | noise indicator |
| `TC` | TX frequency offset |
| `WE` | include weather in BC |
| `TU`, `TE`, `PR`, `HU` | temperature unit, temperature, pressure, humidity |
| `PS` | flag only; device shows "Preset loaded" |
| `DN` | done: `1` save, `2` save and start measuring |

Behaviour:

* Values are applied in RAM immediately. They are written to flash only when
  the line contains `DN` and at least one value changed.
* `BW` (bullet weight) does not count as a change on its own; combine it with
  another key or it will not persist.
* Any saved change clears the device's current result.
* Lines longer than 255 characters are rejected.

Typical exchange:

```
→ $CF
← #V1=30,V2=60,VR=1,BO=0,WU=0,BW=168,DU=0,ST=10,DM=3,D0=100,...!
→ #DM=4,BW=175,DN=1!
   (device shows "Configuration set")
```

## 6. Trying it

### With Chrono Lite from source

1. Set the device's Bluetooth mode to full (this is also what the FX apps
   need). Leave it on the velocity screen.
2. `flutter run` and open the pairing drawer. The device appears by its
   `vXfS3c6k` name; tap it to connect.
3. Fire, or replay a stored shot from the device menu. The velocity shows in
   the app, and the console prints the decoded packet, for example:

   ```
   TrueBallisticClient: TrueBallisticShot(900.0 m/s, 63195 Hz, type 0x0B, BC 0.315 G1)
   TrueBallisticClient: TrueBallisticDownrange(2952.8 fps @0m, 2861.0 @50m, 2771.4 @100m)
   ```

   The second line only appears on firmware that has the `0x162B`
   characteristic.

The BC and downrange values are parsed and exposed on the client
(`TrueBallisticShot.bc`, `.dragModel`, `TrueBallisticClient.downrangeStream`)
but Chrono Lite does not display them. They are there for you to build on.

### With a generic BLE tool

nRF Connect, LightBlue or similar:

1. Scan, connect to the `vXfS3c6k…` device.
2. In service `…1623…`, enable notifications on `…1624…` and `…162B…`.
3. Fire. Decode the `0x1624` bytes using §3; read `0x162B` as text.
4. For configuration, enable notifications on the Nordic UART TX
   characteristic and write `$CF` as text to RX. The reply is the full
   configuration line.

### Without a device

The parser is pure Dart. `test/true_ballistic_parser_test.dart` builds every
packet type from bytes and asserts the decoded values, so you can adapt the
constants there to experiment before touching hardware.
