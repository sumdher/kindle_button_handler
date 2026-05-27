# Kindle Button Handler [BETA]

General-purpose physical button remapper for jailbroken Kindles. KUAL extension.

**Tested on:** Kindle Oasis 3 (KOA3), firmware 5.18.2

---

## Quick Setup

1. Copy `extensions/button_handler` → `/mnt/us/extensions/button_handler`
2. Open KUAL → **Button Handler [BETA]**
3. Run **Capture** for each button (power, next-page, prev-page)
4. Tap **Start**

> No `chmod +x` needed — `/mnt/us` is FAT32. All scripts are invoked via `sh`.

---

## Default Gestures

### Global (always active)

| Gesture | How | Action |
|---|---|---|
| `next_short` | tap next-page | brightness +2 |
| `back_short` | tap prev-page | brightness -2 |
| `back_long` | hold prev-page | go to home screen |
| `power_long` | hold power | show battery + brightness info |
| `back_next_combo` | hold prev, tap next **1×** | toggle dark mode |
| `next_back_combo` | hold next, tap prev **1×** | toggle dark mode |
| `back_next_combo2` | hold prev, tap next **2×** | toggle warm light |
| `next_back_combo2` | hold next, tap prev **2×** | toggle warm light |
| `back_next_combo3` | hold prev, tap next **3×** | warm light +4 |
| `next_back_combo3` | hold next, tap prev **3×** | warm light −4 |

### kindle_browser (active when `kindle_browser` process is running)

| Gesture | How | Action |
|---|---|---|
| `next_short` | tap next-page | brightness +2 |
| `back_short` | tap prev-page | brightness -2 |
| `next_long` | hold next-page | stop browser |
| `back_long` | hold prev-page | reload page (CDP) |
| `back_next_combo` | hold prev, tap next **1×** | toggle dark mode |
| `next_back_combo` | hold next, tap prev **1×** | toggle dark mode |

**Combo technique:** hold the **base** button first, tap the **aux** button N times, then **release the base** to fire. The count appears on screen as you tap.

---

## Adding Your Own Actions

Create a script at `/mnt/us/extensions/button_handler/apps/<profile>/<gesture>` (no `.sh`, no execute bit):

```sh
#!/bin/sh
# example: next_short in a custom profile
lipc-set-prop com.lab126.powerd flIntensity 12
```

**Profile matching** — the directory name is matched against running processes with `pgrep -f <name>`. First match wins; `global_defaults` is the fallback.

To add a new app profile, create the directory and drop scripts in it:

```
apps/
  my_app/         ← active when: pgrep -f my_app
    next_short
    back_short
  global_defaults/ ← always active (fallback)
```

---

## Config

`/mnt/us/extensions/button_handler/config` — edit timing thresholds:

```sh
LONG_PRESS_MS=800    # hold threshold for back/next long press
PWR_LONG_MS=1000     # hold threshold for power long press
TAP_WINDOW_MS=400    # window to count taps after power_long
MAX_TAPS=3           # max taps for power_long_tapN
```

Restart after changes: KUAL → Button Handler → **Restart**.

---

## Useful lipc Commands

```sh
# Brightness (0–24)
lipc-get-prop -i com.lab126.powerd flIntensity
lipc-set-prop    com.lab126.powerd flIntensity 12

# Warm light / amber (0–24)
lipc-get-prop -i com.lab126.powerd currentAmberLevel
lipc-set-prop    com.lab126.powerd currentAmberLevel 12

# Display inversion (dark mode)
lipc-get-prop com.lab126.winmgr epdcMode       # Y8 or Y8INV
lipc-set-prop com.lab126.winmgr epdcMode Y8INV
lipc-set-prop com.lab126.winmgr epdcMode Y8

# Go to home screen
lipc-set-prop com.lab126.KPPMainApp go "KPP_HOME"

# Battery
lipc-get-prop -i com.lab126.powerd battLevel
lipc-get-prop -i com.lab126.powerd isCharging

# Which app is currently in the foreground
lipc-get-prop com.lab126.appmgrd activeApp
# → com.mobileread.ixtab.kindlelauncher  (KUAL)
# → com.lab126.KPPMainApp                (Kindle home)
# → com.notmarek.shell_integration.launcher  (shortcut_browser)

# Wi-Fi
lipc-get-prop    com.lab126.wifid cmState       # CONNECTED / DISCONNECTED
lipc-set-prop    com.lab126.wifid cmd CONNECT
lipc-set-prop    com.lab126.wifid cmd DISCONNECT
```

---

## Troubleshooting

**Daemon won't start / "no config"**
→ Run all three Capture steps first (power, next-page, prev-page), then Start.

**Gestures stop working after launching shortcut_browser**
→ The browser's start script runs `stop lab126_gui`, which would kill any process in the framework's process group. The daemon is started with `setsid` to survive this. If it still dies:
```sh
kill -0 $(cat /tmp/kbh.pid) && echo "ALIVE" || echo "DEAD"
cat /tmp/kbh.log
```

**Wrong app profile is being used**
→ Check which app the OS reports as foreground:
```sh
lipc-get-prop com.lab126.appmgrd activeApp
```
The profile directory name must be a substring of a running process. Use `pgrep -f <name>` to verify:
```sh
pgrep -f kindle_browser && echo "matched" || echo "no match"
```

**KUAL exits to home when pressing Start/Stop**
→ Any stdout from the action script causes KUAL to dismiss. All control paths in the main script redirect to `/dev/null`. If this recurs, check `/tmp/kbh.log` for unexpected output.

**Capture shows nothing / timeout**
→ The daemon is paused during capture. If the button isn't detected, it may be on a different event device. Check manually:
```sh
hexdump -v -e '16/1 "%02X\n"' /dev/input/event0 &
hexdump -v -e '16/1 "%02X\n"' /dev/input/event1 &
hexdump -v -e '16/1 "%02X\n"' /dev/input/event2 &
hexdump -v -e '16/1 "%02X\n"' /dev/input/event3 &
# press the button, observe which device responds
kill %1 %2 %3 %4
```

**Check daemon log:**
```sh
cat /tmp/kbh.log
```

---

## Known Issues

- **Power button events unreliable on Kindle UI** — The Kindle OS also listens to the power button. Events are sometimes consumed before the daemon's `pwr_reader` sees them. Power gestures work more reliably when the framework is not intercepting input (e.g., during browser fullscreen).
- **Events not captured reliably in KUAL** — The Capture wizard pauses the daemon, but KUAL itself may consume key events. If a capture times out, try again or capture from SSH.
- **shortcut_browser wrapper process lingers** — After running `stopbr`, the wrapper script (`shortcut_browser.sh`) stays alive in a power-button polling loop until the power button is physically pressed. This is harmless but occupies a process slot.

---

## Contributing — Adding Your Device

Edit `devices.json` with your button codes:

```json
"MODEL": {
  "name": "Kindle Model Name",
  "aliases": ["codename"],
  "fw": ["5.x.x"],
  "buttons": {
    "power": {"event": "event1", "hex_code": "7400"},
    "next":  {"event": "event3", "hex_code": "6800"},
    "back":  {"event": "event3", "hex_code": "6D00"}
  }
}
```

`hex_code` = little-endian 4-char hex from hexdump (key 116 = 0x74 → `7400`). Run the Capture wizard to find your codes automatically.
