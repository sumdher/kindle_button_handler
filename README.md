# Kindle Button Handler [BETA]

General-purpose (app-specific rules) physical button remapper for [jailbroken](https://kindlemodding.org/jailbreaking/index.html) Kindles. Runs as a [KUAL](https://kindlemodding.org/jailbreaking/post-jailbreak/installing-kual-mrpi/) extension.

**Tested on:** Kindle Oasis 3 (KOA3), firmware 5.18.2

> *Basic bash knowledge helps if you want to customize actions.*

---

## Setup

1. Copy `extensions/button_handler` to your kindle's `/mnt/us/extensions/button_handler`.
2. Open KUAL → **Button Handler [BETA]** > run **Capture** for each button (power, next, prev)
3. Tap **Start**
4. To configure actions on triggers, see [this section](#customizing).

---

## Default Actions

### Global (always active)

| Trigger | Action |
|---|---|
| tap next-page | brightness +2 |
| tap prev-page | brightness −2 |
| hold prev-page | go to home screen |
| hold next-page | -- do nothing -- |
| hold power [*](#known-issues) | show battery + brightness |
| hold prev + tap next **1×** | toggle dark mode |
| hold next + tap prev **1×** | toggle dark mode |
| hold prev + tap next **2×** | toggle warm light |
| hold next + tap prev **2×** | toggle warm light |
| hold prev + tap next **3×** | warm light +4 |
| hold next + tap prev **3×** | warm light −4 |


### Example for ['shortcut\_browser'](https://github.com/mitchellurgero/kindle-shortcut-browser)

Active when `kindle_browser` (its pname) process runs.

If it doesn't work for you, see this: [Wrong profile firing](#foreground_troubleshoot) to get the foreground app reliably.


| Trigger | Action |
|---|---|
| tap next-page | brightness +2 |
| tap prev-page | brightness −2 |
| hold next-page | stop browser |
| hold prev-page | reload page (CDP) |
| hold prev + tap next **1×** | toggle dark mode |
| hold next + tap prev **1×** | toggle dark mode |

**Combo:** hold base → tap aux N times → **release base** to fire. Count shown on screen.

---

## Customizing

Drop a script at `/mnt/us/extensions/button_handler/apps/<profile>/<gesture>` (no `.sh`, no execute bit). The profile directory name is matched against running processes via `pgrep -f`. `global_defaults` is always the fallback.

Gesture names: `next_short`, `next_long`, `back_short`, `back_long`, `power_long`, `power_long_tap1`…`tapN`, `back_next_combo`, `back_next_combo2`…`comboN`, `next_back_combo`, `next_back_combo2`…`comboN`.

Timing config at `/mnt/us/extensions/button_handler/config`:
```sh
LONG_PRESS_MS=800   # hold threshold (next/prev)
PWR_LONG_MS=1000    # hold threshold (power)
TAP_WINDOW_MS=400   # tap window after power_long
MAX_TAPS=3
```

---

## Useful Commands

```sh
# Brightness / warm light (0–24)
lipc-get-prop -i com.lab126.powerd flIntensity
lipc-set-prop    com.lab126.powerd flIntensity 12
lipc-get-prop -i com.lab126.powerd currentAmberLevel
lipc-set-prop    com.lab126.powerd currentAmberLevel 12

# Dark mode
lipc-get-prop com.lab126.winmgr epdcMode        # Y8 or Y8INV
lipc-set-prop com.lab126.winmgr epdcMode Y8INV

# Home screen
lipc-set-prop com.lab126.KPPMainApp go "KPP_HOME"

# Battery
lipc-get-prop -i com.lab126.powerd battLevel
lipc-get-prop -i com.lab126.powerd isCharging

# Foreground app
lipc-get-prop com.lab126.appmgrd activeApp
# com.mobileread.ixtab.kindlelauncher     → KUAL
# com.lab126.KPPMainApp                   → Kindle home
# com.notmarek.shell_integration.launcher → shortcut_browser

# Wi-Fi
lipc-set-prop com.lab126.wifid cmd CONNECT
lipc-set-prop com.lab126.wifid cmd DISCONNECT
```

---

## Troubleshooting

**"no config" on start** — run all three Capture steps first.

**Actions stop working after browser launch** — the browser kills `lab126_gui` on start, which would take down framework children. The daemon uses `setsid` to survive this. Verify:
```sh
kill -0 $(cat /tmp/kbh.pid) && echo "ALIVE" || echo "DEAD"
cat /tmp/kbh.log
```

<a id="foreground_troubleshoot"></a>

**Wrong profile firing** — check foreground app and verify pgrep matches:
```sh
lipc-get-prop com.lab126.appmgrd activeApp
pgrep -f kindle_browser && echo "matched" || echo "no match"
```

**Capture times out** — find the right event device manually:
```sh
for i in 0 1 2 3; do hexdump -v -e '16/1 "%02X\n"' /dev/input/event$i & done
# press the button, note which device printed output, then: kill %1 %2 %3 %4
```

**Check daemon log:** `cat /tmp/kbh.log`

---

## Known Issues

- **Power button overrides don't work** — the OS intercepts power events; detection is inconsistent while the framework is running.
- **Prev & next butons unreliable in Kindle UI** — similarly, Kindle UI listens on prev and next buttons to scroll the UI. The trigger capturing on this particular home page is a hit-or-miss.

---

<!-- ## Hey there!

If you are reading this, you seem to be interested in this project. Please add your Kindle device's key codes here so we can have a comprehensive dictionary for all the kindle devices. 

Thank you.

### Adding Your Device (Optional)

Edit `devices.json` with your button event and hex code (from Capture or hexdump):
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
``` -->
