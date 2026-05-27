# Kindle Button Handler [BETA]

General-purpose physical button remapper for jailbroken Kindles.
Compatible with **KUAL**.

Tested on: Kindle Oasis 10th gen (KOA3), firmware 5.18.2.

---

## Repository layout

```
kindle_button_handler/
│
├── extensions/
│   └── button_handler/          ← copy this entire folder to /mnt/us/extensions/
│       ├── config.xml               KUAL extension manifest
│       ├── menu.json                KUAL menu definition (start/stop/capture/status)
│       └── button_handler_main.sh   daemon control + button capture logic
│
├── documents/
│   └── button_handler/          ← copy this entire folder to /mnt/us/documents/
│       └── apps/
│           ├── default/             fires when no specific app is matched
│           │   ├── next_short       quick tap → brightness +2
│           │   ├── next_long        hold      → brightness max
│           │   ├── back_short       quick tap → brightness -2
│           │   ├── back_long        hold      → brightness off
│           │   ├── power_long       hold      → show battery + brightness on screen
│           │   ├── power_long_tap1  power-hold + 1 tap → toggle brightness on/off
│           │   ├── back_next_combo  hold prev + tap next → toggle Wi-Fi
│           │   └── next_back_combo  hold next + tap prev → go to home/library
│           └── kindle_browser/      fires only when kindle_browser is running
│               ├── next_short       quick tap → brightness +2
│               └── back_short       quick tap → brightness -2
│
├── devices.json                 Community button key-code database (reference only)
└── README.md
```

---

## Installation

### 1 — Copy extension files (KUAL launcher)

```sh
cp -r extensions/button_handler /mnt/us/extensions/
chmod +x /mnt/us/extensions/button_handler/button_handler_main.sh
```

### 2 — Copy action scripts (user data)

```sh
cp -r documents/button_handler /mnt/us/documents/
chmod +x /mnt/us/documents/button_handler/apps/default/*
chmod +x /mnt/us/documents/button_handler/apps/kindle_browser/*
```

> **Note:** The `/mnt/us/documents/button_handler/` directory is created automatically
> on first run if it doesn't exist. You only need to copy it if you want the
> pre-built action scripts.

### 3 — Open KUAL

**Button Handler [BETA]** will appear in the KUAL menu.

---

## First-time setup (button capture)

The daemon needs to know which physical button is which. Run this once:

1. KUAL → Button Handler → **Capture: POWER button** → press the power button
2. KUAL → Button Handler → **Capture: NEXT PAGE button** → press next-page
3. KUAL → Button Handler → **Capture: PREV PAGE button** → press prev-page

After each capture the bottom of the screen shows the detected event device and key code.
Results are saved to `/mnt/us/documents/button_handler/config`.

Then tap **Start**. The menu shows **Daemon: RUNNING**.

---

## Gesture reference

| Gesture name | How to trigger |
|---|---|
| `next_short` | Next-page button: quick tap |
| `next_long` | Next-page button: hold ≥ `LONG_PRESS_MS` |
| `back_short` | Prev-page button: quick tap |
| `back_long` | Prev-page button: hold ≥ `LONG_PRESS_MS` |
| `back_next_combo` | Hold prev-page, tap next-page |
| `next_back_combo` | Hold next-page, tap prev-page |
| `power_long` | Power button: hold ≥ `PWR_LONG_MS` |
| `power_long_tap1` | Power hold, then 1 quick tap |
| `power_long_tap2` | Power hold, then 2 quick taps |
| `power_long_tapN` | Power hold, then N taps (up to `MAX_TAPS`) |

---

## Writing action scripts

Each gesture slot is a plain executable shell script. Create it at:

```
/mnt/us/documents/button_handler/apps/<profile>/<gesture>
```

Example — scroll down in the browser on next-page tap:

```sh
mkdir -p /mnt/us/documents/button_handler/apps/kindle_browser

cat > /mnt/us/documents/button_handler/apps/kindle_browser/next_short << 'EOF'
#!/bin/sh
lipc-set-prop com.lab126.browser jsEval 'window.scrollBy(0, 300)'
EOF

chmod +x /mnt/us/documents/button_handler/apps/kindle_browser/next_short
```

### Profile matching

The **directory name** is matched against running processes with `pgrep -f <name>`.
First match wins. `default` always fires as fallback.

```
apps/kindle_browser/    → active when: pgrep -f kindle_browser
apps/com.lab126.reader/ → active when: pgrep -f com.lab126.reader
apps/default/           → always active (fallback)
```

### Useful lipc commands

```sh
# Brightness (0–24)
lipc-get-prop -i com.lab126.powerd flIntensity
lipc-set-prop    com.lab126.powerd flIntensity 12

# Battery
lipc-get-prop -i com.lab126.powerd battLevel
lipc-get-prop -i com.lab126.powerd isCharging

# Wi-Fi
lipc-get-prop    com.lab126.wifid cmState          # connected / disconnected
lipc-set-prop    com.lab126.wifid cmd CONNECT
lipc-set-prop    com.lab126.wifid cmd DISCONNECT

# Go to home screen
lipc-set-prop com.lab126.appmgr start '{"id":"com.lab126.booklet"}'
```

---

## Config file

Located at `/mnt/us/documents/button_handler/config`. Edit to tune timing:

```sh
LONG_PRESS_MS=800       # hold threshold for back/next long press
PWR_LONG_MS=1000        # hold threshold for power long press
TAP_WINDOW_MS=400       # window to count taps after power_long
MAX_TAPS=3              # fire immediately when tap count reaches this

BTN_POWER_EVENT=event1  # set by Capture wizard
BTN_POWER_CODE=7400
BTN_NEXT_EVENT=event3
BTN_NEXT_CODE=6800
BTN_BACK_EVENT=event3
BTN_BACK_CODE=6D00
```

Restart the daemon after changes: KUAL → Button Handler → **Restart**.

---

## Runtime files

| Path | Purpose |
|---|---|
| `/tmp/kbh.pid` | Daemon PID |
| `/tmp/kbh.log` | Daemon log (errors, startup) |
| `/tmp/kbh_pp` `/tmp/kbh_pr` | Power button press/release timestamps (IPC) |

---

## Contributing — adding your device

Edit `devices.json`:

```json
"KOA3": {
  "name": "Kindle Oasis 10th gen",
  "aliases": ["rex"],
  "fw": ["5.18.2"],
  "buttons": {
    "power": {"event": "event1", "hex_code": "7400"},
    "next":  {"event": "event3", "hex_code": "6800"},
    "back":  {"event": "event3", "hex_code": "6D00"}
  }
}
```

`hex_code` is the little-endian 4-char hex from `hexdump` output.
Key 116 (0x74) → `7400`. Run the Capture wizard to find your codes automatically.

Submit a PR with your device entry and tested firmware version.
