# FiiO K17 network protocol

Reverse-engineered from the FiiO Control app talking to a K17 (firmware 265,
`soc_version` 265). Unofficial; may change with firmware updates.

## Transport

- TCP port **12100** on the K17 (`mq_player`, module `fiio_link`).
- **One client at a time.** After a client disconnects the device needs about one
  second before it accepts the next connection.

## Framing

Every message is ASCII:

```
CCCC LLLL PAYLOAD
```

- `CCCC`: command, 4 hex characters.
- `LLLL`: total frame length in characters (header included), 4 hex digits.
- Replies use the command with its first digit replaced by `a`
  (`0502` → `a502`). Case varies, compare case-insensitively.
- The device sends frames on its own as well, e.g. `a60a000C000C` before every
  volume acknowledgement and `a627…` after an EQ change. Read frames by length and
  match the reply by command instead of assuming the next frame is the answer.

## Commands

| Request | Reply | Meaning |
|---|---|---|
| `05010008` | `a501` + JSON | Status: `currentVolume`, `maxVolume` (100), `muteMode`, … |
| `0502000c` + `%04X` | `a502000C%04X` | Set volume 0-100 |
| `0639000c0000` | `a639000C%04X` | Get EQ |
| `0690000c` + `%04X` | `a639000C%04X` | Set EQ |
| `062700100000A0A9` | `a627` + `A0A9` + hex | Names of custom EQs A0-A9, 10 NUL-padded 8-byte slots |
| `062800100000001E` | `a628` + hex | EQ curve of the active preset |
| `0607000c0000` | `a607000C%04X` | Get input |
| `0657000c` + `%04X` | `a607000C%04X` | Set input. Takes a few seconds and sometimes needs a resend; no reply at all when the input is already active |
| `0202 0008` | `a2020013{"state":N}` | Playback state |

### EQ codes

| Code | Preset |
|---|---|
| `FF` | Off |
| `00`–`06` | Jazz, Rock, R&B, Hip-Hop, Pop, Dance, Classical |
| `A0`–`A9` | Custom 1–10 |

### Input codes

| Code | Input |
|---|---|
| 1 | USB |
| 2 | Optical |
| 3 | Coaxial |
| 4 | Line In |
| 5 | Balanced In |
| 6 | Bluetooth |
| 7 | Streaming |
| 8 | Local Play |

## EQ bands

Every EQ has **31** bands (0–30). `0628` returns them for the active EQ; the
second number is the index of the last band:

```
a628 LLLL 0000 001E  [31 × band]
band = GGGG FFFF QQQQ TT   (7 bytes, hex)
```

| Field | Encoding |
|---|---|
| `GGGG` gain | `120 + dB × 5`, i.e. 0.2 dB steps, 120 = 0 dB, range ±12 dB |
| `FFFF` frequency | `1 + 120 × log10(Hz / 20)`: 120 steps per decade from 20 Hz (1) to 20 kHz (361) |
| `QQQQ` Q | `Q × 10 + 8` (16 = Q 0.8, the presets' default). FiiO's own presets also use raw values below 8; keep unknown values as they are. |
| `TT` type | 0 peak, 1 low shelf, 2 high shelf |

The presets are 10-band graphic EQs on bands 2, 5, …, 29 (31 Hz … 16 kHz). Unused bands sit at 1, 12, 24, …, 360 on the frequency scale.

There is no preamp: the app imports AutoEQ profiles as bands only.

Writing (custom EQs A0–A9 only, the active one):

| Request | Reply | Meaning |
|---|---|---|
| `0678` LLLL `0000` NNNN + bands | none | Apply bands live. `NNNN` is the index of the last band and bands start at band 0, so send all 31 (`0000001E` + 31 bands, length `01C2`), as the app does. Claiming more bands than you send makes the device read garbage. |
| `0626000c0000` | none | Store the active custom EQ on the device |
| `0675000c0000` | `a639…` | Flatten the active custom EQ **and store it** (no `0626` needed, there is no undo) |

Unsaved band changes are dropped when the EQ is switched.

Renaming:

| Request | Reply | Meaning |
|---|---|---|
| `0677` LLLL `0000` SSEE + names | `a627` LLLL SSEE + names | Rename custom slots SS…EE (e.g. `A1A1`), 8 NUL-padded bytes (UTF-8) per slot. Stored at once. |

## Not available over the network

- **Mute.** The app's speaker icon sends `0716000c0001`, which the firmware ignores.
  The knob-press mute is handled by the K17's microcontroller and is not reported.

## Discovery

While no client is connected the K17 sends the 3 bytes `K17` to
`224.0.0.255:12101` every 2 seconds (link-local, so same network segment only).

## Notes

- Volume changes made on the knob are reflected in the `05010008` status immediately.
