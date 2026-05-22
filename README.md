# Kindle Button Handler [BETA]

General-purpose physical button remapper for jailbroken Kindles.
Compatible with **KUAL** and **KindleForge**.

Tested on: Kindle Oasis 10th gen (KOA3), firmware 5.18.2.
Other models need community-contributed key codes — see [Contributing](#contributing).

---

## What it does

Maps physical buttons (previous page, next page, power) to arbitrary shell commands.
Bindings are **per-app**: when a configured process is running, its gesture scripts are active.
Falls back to a `default` profile when no app matches.

### Supported gestures

| Gesture | Description |
|---|---|
| `back_short` | Previous-page button: quick tap |
| `back_long` | Previous-page button: hold ≥ `LONG_PRESS_MS` |
| `next_short` | Next-page button: quick tap |
| `next_long` | Next-page button: hold ≥ `LONG_PRESS_MS` |
| `power_long` | Power button: hold ≥ `PWR_LONG_MS` |
| `power_long_tap1` | Power long press, then 1 quick tap |
| `power_long_tap2` | Power long press, then 2 quick taps |
| `power_long_tapN` | Power long press, then N taps (up to `MAX_TAPS`) |
| `back_next_combo` | Hold previous-page, tap next-page |
| `next_back_combo` | Hold next-page, tap previous-page |

All timing thresholds are configurable per millisecond.

---

## Files

```
kindle_button_handler/
├── button_main.sh    entry point (shown in library), daemon control, wizard
├── handler           gesture engine — runs as background daemon
├── menu.json         KUAL extension menu definition
├── devices.json      community database of device button key codes
└── README.md
```

Only `button_main.sh` has a `.sh` extension — all `.sh` files under `/mnt/us/` appear
in the Kindle library. Everything else is intentionally extension-free.

---

## Installation

### As a KUAL extension (recommended)

```sh
cp -r kindle_button_handler /mnt/us/extensions/button_handler
```

KUAL will show **Button Handler [BETA]** in its menu.

### Standalone (Kindle library)

```sh
cp -r kindle_button_handler /mnt/us/button_handler
```

`button_main.sh` will appear in the Kindle library. Tap it to open.

---

## First run

On first launch, if no config exists, the button wizard starts automatically.

**Wizard flow:**

1. One button at a time, it prompts: *"Press and hold POWER / NEXT PAGE / PREV PAGE, then release."*
2. It listens across all `/dev/input/event*` devices simultaneously.
3. The first key press event wins — device path and hex code are recorded.
4. After all three buttons, results are saved to `/mnt/us/documents/button_handler/config`.

> **Important:** Press *only* the button shown on screen. The wizard captures
> whatever comes first — it cannot tell if you pressed the wrong one.

You can re-run the wizard any time from the KUAL menu or with:
```sh
button_main.sh wizard           # recapture all buttons
button_main.sh wizard power     # recapture only power
button_main.sh wizard next
button_main.sh wizard back
```

---

## User data directory

All runtime data lives at `/mnt/us/documents/button_handler/` and is created on first run.

```
/mnt/us/documents/button_handler/
├── config                   timing thresholds + captured button codes
└── apps/
    ├── default/             always-active fallback profile
    │   ├── next_short       action script (executable shell file)
    │   └── back_short
    └── kindle_browser/      active when "kindle_browser" process is running
        ├── next_short
        ├── back_short
        ├── back_long
        └── power_long
```

### Config file format

```sh
# Timing (milliseconds)
LONG_PRESS_MS=800        # hold threshold for back/next long press
PWR_LONG_MS=1000         # hold threshold for power long press
TAP_WINDOW_MS=400        # window to count taps after power_long
MAX_TAPS=3               # fire immediately when tap count reaches this

# Button codes (set by wizard — edit manually if you know your codes)
BTN_POWER_EVENT=event1
BTN_POWER_CODE=7400
BTN_NEXT_EVENT=event3
BTN_NEXT_CODE=6800
BTN_BACK_EVENT=event3
BTN_BACK_CODE=6D00
```

Edit this file to tune timing. Restart the daemon after changes.

---

## Action scripts

Each gesture slot is an executable shell script you place in the app directory.
The script is run in the background when the gesture fires.

### Example: brightness control for kindle_browser

```sh
mkdir -p /mnt/us/documents/button_handler/apps/kindle_browser

# next_short → increase brightness
cat > /mnt/us/documents/button_handler/apps/kindle_browser/next_short << 'EOF'
#!/bin/sh
cur=$(lipc-get-prop com.lab126.powerd flIntensity)
new=$((cur + 2)); [ "$new" -gt 24 ] && new=24
lipc-set-prop com.lab126.powerd flIntensity "$new"
EOF

chmod +x /mnt/us/documents/button_handler/apps/kindle_browser/next_short
```

### App matching

The **directory name** is used as the `pgrep` pattern to detect if the app is running.
The first matching app wins. `default` is always the fallback (matched when nothing else does).

```
apps/kindle_browser/    → active when: pgrep -f kindle_browser
apps/com.amazon.ebook/  → active when: pgrep -f com.amazon.ebook
apps/default/           → always active (fallback)
```

### Available action scripts (gesture names)

```
back_short    back_long
next_short    next_long
power_long
power_long_tap1  power_long_tap2  power_long_tap3  (up to MAX_TAPS)
back_next_combo  next_back_combo
```

---

## Daemon management

```sh
button_main.sh start     # start the gesture engine in background
button_main.sh stop      # stop it
button_main.sh restart   # restart
button_main.sh           # show status screen
```


Or use the KUAL menu items.

- PID file: `/tmp/kbh.pid`
- Log file: `/tmp/kbh.log`

---

## Architecture

```
button_main.sh
  ├── on first run (no config)   → runs wizard
  ├── wizard                     → listens on all event devices, saves config
  ├── start/stop/restart         → manages handler process via PID file
  └── status                     → eips display of current state

handler (daemon)
  ├── sources config             → loads button codes and timing
  ├── pwr_reader (background)    → reads power button, writes timestamps to /tmp
  ├── check_power()              → detects power gestures from temp files
  ├── main loop                  → blocks on page button device
  │     reads events → detects short/long/combo gestures
  └── fire()                     → finds active app, runs gesture script
```

**Why two processes for power?**
Power is typically on a different `/dev/input/eventX` than the page buttons.
A single `dd` call blocks on one device. The background `pwr_reader` writes press/release
timestamps to temp files; the main loop reads those non-blocking at the top of each iteration.

---

## Beta limitations

- **Back and next must share the same event device.** If your model has them on separate
  devices, back gestures are disabled. A FIFO-based redesign will fix this in a future version.

- **Power tap-window expiry is lazy.** After `power_long + taps`, the gesture fires on the
  next page-button event rather than at exact window expiry. Acceptable in practice.

- **eips grid size** is hardcoded for KOA3 (~40 cols). The wizard UI may look off on other
  screen sizes. Adjust the `eips` coordinates in `button_main.sh` if needed.

---

## Contributing

### Adding your device to `devices.json`

Open `devices.json` and add an entry:

```json
"KOA3": {
  "name": "Kindle Oasis 10th gen",
  "aliases": ["rex"],
  "fw": ["5.18.2"],
  "by": ["your_handle"],
  "buttons": {
    "power": {"event": "event1", "hex_code": "7400"},
    "next":  {"event": "event3", "hex_code": "6800"},
    "back":  {"event": "event3", "hex_code": "6D00"}
  }
}
```

**`hex_code`** is the little-endian 4-char hex string from `hexdump` output.
Key code 116 (0x74) becomes `7400`. Key code 109 (0x6D) becomes `6D00`.

**How to find your codes manually:**

```sh
dd if=/dev/input/event3 bs=16 count=1 | hexdump -v -e '16/1 "%02X"'
```

Press the button and read chars 20–23 from the output. Or just run the wizard —
it finds the code and device automatically.

**Device codename** (`aliases`) can be found at:
```sh
cat /proc/usid
# or
lipc-get-prop com.lab126.platform boardId
```

Submit a PR with your device entry and tested firmware version. Community contributions
are what make this work across all Kindle models.
