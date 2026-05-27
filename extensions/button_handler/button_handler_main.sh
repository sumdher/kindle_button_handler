#!/bin/sh
# Kindle Button Handler [BETA]
# KUAL extension + library shortcut.
#
# From KUAL menu   : each item calls this script with a specific action arg.
#                    menu.sh (dynamic) handles live status display.
# From SSH/terminal: same args work, echo output goes to terminal.
#
# Action scripts: /mnt/us/extensions/button_handler/apps/<process>/<gesture>

DATA="/mnt/us/extensions/button_handler"
PID="/tmp/kbh.pid"

# ── Helpers ──────────────────────────────────────────────────────────────────
running() { local p; p=$(cat "$PID" 2>/dev/null) && kill -0 "$p" 2>/dev/null; }

# ── eips display (mirrors libkh5 kh_eips_print behavior) ─────────────────────
# Width : virtual_size first field = xres_virtual (line_length) = 1280 on KOA3.
#         libkh5 uses this, not the physical xres (1264) from modes.
# Height: modes file physical yres = 1680 on KOA3.
# Char cell: 16x24 px on all modern Kindles (libkh5 confirmed).
_kbh_virtw=$(cut -d, -f1 /sys/class/graphics/fb0/virtual_size 2>/dev/null)
_kbh_physh=$(cat /sys/class/graphics/fb0/modes 2>/dev/null | grep -o 'x[0-9]*' | head -1 | tr -d 'x')
EIPS_COLS=$(( ${_kbh_virtw:-1280} / 16 ))
EIPS_ROWS=$(( ${_kbh_physh:-1680} / 24 ))

# Write a padded line at a given row. Padding erases any previous text.
_eips() {
    local msg="$1" row="$2"
    while [ "${#msg}" -lt "$EIPS_COLS" ]; do msg="$msg "; done
    eips 0 "$row" "$msg" >/dev/null 2>&1
}

# Single-line message at bottom row (libkh5 kh_eips_print style).
kh_msg() { _eips "$1" $(( EIPS_ROWS - 2 )); }

# Gesture notification at row 0 (top / status bar area).
# Shows "▸ <gesture>" for 5s, then erases by overwriting with spaces.
# The Kindle OS redraws its own status bar on the next UI refresh.
_notif() {
    _eips "  > $1" 0
    ( sleep 5; _eips "" 0 ) &
}

# Multi-line block written into the bottom N rows — no screen clear.
# KUAL renders in the upper portion; bottom rows are free for our use.
_eips_block() {
    # Args: row_offset_from_bottom  line1  line2 ...
    local base=$(( EIPS_ROWS - $1 )); shift
    local i=0
    for line in "$@"; do
        _eips "$line" $(( base + i ))
        i=$(( i + 1 ))
    done
}

# Full-screen config dump (clears screen — invoked by status/info menu item)
info() {
    eips -c >/dev/null 2>&1
    local row=3
    if running; then
        _eips "Daemon : RUNNING  (PID $(cat "$PID" 2>/dev/null))" $row
    else
        _eips "Daemon : STOPPED" $row
    fi
    row=$(( row + 2 ))
    if [ -f "$DATA/config" ]; then
        . "$DATA/config"
        _eips "Power : /dev/input/$BTN_POWER_EVENT  code $BTN_POWER_CODE" $row
        _eips "Next  : /dev/input/$BTN_NEXT_EVENT   code $BTN_NEXT_CODE"  $(( row + 1 ))
        _eips "Prev  : /dev/input/$BTN_BACK_EVENT   code $BTN_BACK_CODE"  $(( row + 2 ))
        _eips "long=${LONG_PRESS_MS}ms  pwr=${PWR_LONG_MS}ms  win=${TAP_WINDOW_MS}ms  max=${MAX_TAPS}" $(( row + 4 ))
    else
        _eips "No config -- run Capture for each button first" $row
    fi
    _eips "[ tap anywhere to dismiss ]" $(( row + 7 ))
}

# Per-button detail view — writes into the bottom 8 rows, no screen clear.
show_btn() {
    [ -f "$DATA/config" ] || { kh_msg "KBH: no config yet"; return; }
    . "$DATA/config"
    local ev code gestures threshold
    case "$1" in
        power)
            ev=$BTN_POWER_EVENT; code=$BTN_POWER_CODE
            gestures="power_long  power_long_tap1..${MAX_TAPS:-3}"
            threshold="Hold >= ${PWR_LONG_MS:-1000}ms"
            ;;
        next)
            ev=$BTN_NEXT_EVENT; code=$BTN_NEXT_CODE
            gestures="next_short  next_long  back_next_combo"
            threshold="Long >= ${LONG_PRESS_MS:-800}ms"
            ;;
        back)
            ev=$BTN_BACK_EVENT; code=$BTN_BACK_CODE
            gestures="back_short  back_long  next_back_combo"
            threshold="Long >= ${LONG_PRESS_MS:-800}ms"
            ;;
        *) kh_msg "KBH: unknown button $1"; return ;;
    esac
    _eips_block 9 \
        "[ $1 button ]" \
        "" \
        "  Device   : /dev/input/$ev" \
        "  Key code : 0x$code" \
        "  Threshold: $threshold" \
        "  Gestures : $gestures"
}

# ── Daemon control ────────────────────────────────────────────────────────────
start_d() {
    if running; then kh_msg "KBH: already running (PID $(cat "$PID"))"; return; fi
    if [ ! -f "$DATA/config" ]; then kh_msg "KBH: no config -- run Capture first"; return; fi
    sh "$0" __daemon >> /tmp/kbh.log 2>&1 &
    echo $! > "$PID"; sleep 1
    if running; then
        kh_msg "KBH: started (PID $(cat "$PID"))"
    else
        kh_msg "KBH: failed to start -- check /tmp/kbh.log"
    fi
}

stop_d() {
    if ! running; then rm -f "$PID"; kh_msg "KBH: not running"; return; fi
    local p; p=$(cat "$PID")
    # Kill process group so pwr_reader child dies too
    kill -- -"$p" 2>/dev/null || kill "$p" 2>/dev/null
    rm -f "$PID"
    kh_msg "KBH: stopped"
}

status() {
    info
}

# ── Button capture ────────────────────────────────────────────────────────────
# Listen on all event devices for one key press (up to 12s).
# Prints "eventN:HEXCODE" or empty on timeout.
_cap() {
    local cap="/tmp/kbh_cap$$" i=0 pids=""
    mkdir -p "$cap"
    while [ "$i" -le 7 ]; do
        [ -e "/dev/input/event$i" ] && {
            local n=$i
            ( while true; do
                ev=$(dd if="/dev/input/event$n" bs=16 count=1 2>/dev/null | hexdump -v -e '16/1 "%02X"')
                type="${ev:16:4}"; code="${ev:20:4}"; val="${ev:24:8}"
                [ "$type" = "0100" ] && [ "$val" = "01000000" ] && [ "$code" != "0000" ] || continue
                [ -f "$cap/r" ] && exit 0
                printf "event%s:%s" "$n" "$code" > "$cap/r.tmp" && mv "$cap/r.tmp" "$cap/r"
                exit 0
            done ) &
            pids="$pids $!"
        }
        i=$((i + 1))
    done
    sleep 12 &
    local sp=$!
    while kill -0 "$sp" 2>/dev/null && [ ! -f "$cap/r" ]; do sleep 1; done
    kill "$sp" 2>/dev/null
    kill $pids 2>/dev/null; wait 2>/dev/null
    [ -f "$cap/r" ] && cat "$cap/r"
    rm -rf "$cap"
}

cap_btn() {
    local btn="$1"   # power | next | back
    local LOG="/tmp/kbh.log"

    echo "$(date) cap_btn[$btn]: starting" >> "$LOG"

    # Write feedback to row 1 (top area) — visible above KUAL's menu items
    # and also to the bottom row for good measure
    _eips "> KBH CAPTURE $btn: press button now (12s)..." 1
    kh_msg   "KBH capture: press the $btn button now (12s)..."

    running && kill -STOP "$(cat "$PID")" 2>/dev/null
    touch /tmp/kbh_paused

    r=$(_cap)

    rm -f /tmp/kbh_paused
    running && kill -CONT "$(cat "$PID")" 2>/dev/null

    echo "$(date) cap_btn[$btn]: result='$r'" >> "$LOG"

    if [ -z "$r" ]; then
        _eips "> KBH CAPTURE $btn: TIMEOUT -- nothing detected" 1
        kh_msg "KBH capture timeout: $btn -- nothing detected"
        return 1
    fi

    ev="${r%%:*}"; code="${r##*:}"

    # Write default config if missing
    mkdir -p "$DATA"
    if [ ! -f "$DATA/config" ]; then
        cat > "$DATA/config" << EOF
LONG_PRESS_MS=800
PWR_LONG_MS=1000
TAP_WINDOW_MS=400
MAX_TAPS=3
BTN_POWER_EVENT=event1
BTN_POWER_CODE=7400
BTN_NEXT_EVENT=event3
BTN_NEXT_CODE=6800
BTN_BACK_EVENT=event3
BTN_BACK_CODE=6D00
EOF
    fi

    # Update only the relevant lines
    case "$btn" in
        power)
            sed -i "s/^BTN_POWER_EVENT=.*/BTN_POWER_EVENT=$ev/" "$DATA/config"
            sed -i "s/^BTN_POWER_CODE=.*/BTN_POWER_CODE=$code/" "$DATA/config"
            ;;
        next)
            sed -i "s/^BTN_NEXT_EVENT=.*/BTN_NEXT_EVENT=$ev/" "$DATA/config"
            sed -i "s/^BTN_NEXT_CODE=.*/BTN_NEXT_CODE=$code/" "$DATA/config"
            ;;
        back)
            sed -i "s/^BTN_BACK_EVENT=.*/BTN_BACK_EVENT=$ev/" "$DATA/config"
            sed -i "s/^BTN_BACK_CODE=.*/BTN_BACK_CODE=$code/" "$DATA/config"
            ;;
    esac

    _eips "> KBH CAPTURED $btn: /dev/input/$ev  code $code" 1
    kh_msg "KBH captured $btn: /dev/input/$ev  code $code"
    echo "$(date) cap_btn[$btn]: saved ev=$ev code=$code" >> "$LOG"
}

# ── Gesture engine (__daemon — do not call directly) ─────────────────────────
daemon_run() {
    [ -f "$DATA/config" ] || { echo "no config" >&2; exit 1; }
    . "$DATA/config"

    LONG_PRESS_MS="${LONG_PRESS_MS:-800}"
    PWR_LONG_MS="${PWR_LONG_MS:-1000}"
    TAP_WINDOW_MS="${TAP_WINDOW_MS:-400}"
    MAX_TAPS="${MAX_TAPS:-3}"
    DEV_PWR="/dev/input/${BTN_POWER_EVENT:-event1}"
    DEV_PAGE="/dev/input/${BTN_NEXT_EVENT:-event3}"
    NEXT_CODE="${BTN_NEXT_CODE:-6800}"
    BACK_CODE="${BTN_BACK_CODE:-6D00}"
    PWR_CODE="${BTN_POWER_CODE:-7400}"
    T="/tmp/kbh"

    ms() { awk '{printf "%d\n", $1*1000}' /proc/uptime; }

    fire() {
        local g="$1" s="" app nm
        for app in "$DATA/apps"/*/; do
            nm="${app%/}"; nm="${nm##*/}"
            [ "$nm" = "global_defaults" ] && continue
            pgrep -f "$nm" >/dev/null 2>&1 || continue
            [ -f "${app}${g}" ] && s="${app}${g}" && break
        done
        [ -z "$s" ] && [ -f "$DATA/apps/global_defaults/$g" ] && s="$DATA/apps/global_defaults/$g"
        if [ -n "$s" ]; then
            _notif "$g"
            sh "$s" &
        fi
    }

    pwr_reader() {
        while true; do
            ev=$(dd if="$DEV_PWR" bs=16 count=1 2>/dev/null | hexdump -v -e '16/1 "%02X"')
            t="${ev:16:4}"; c="${ev:20:4}"; v="${ev:24:8}"
            [ "$t" = "0100" ] && [ "$c" = "$PWR_CODE" ] || continue
            [ "$v" = "01000000" ] && ms > "${T}_pp"
            [ "$v" = "00000000" ] && ms > "${T}_pr"
        done
    }

    pwr_last=0; pwr_long=0; pwr_taps=0; pwr_win=0

    chk_pwr() {
        local pp pr now hold age
        pp=$(cat "${T}_pp" 2>/dev/null); pr=$(cat "${T}_pr" 2>/dev/null)
        [ -z "$pp" ] || [ -z "$pr" ] && return
        now=$(ms)
        if [ "$pr" = "$pwr_last" ]; then
            [ "$pwr_long" = "1" ] && [ "$pwr_win" -gt 0 ] && {
                age=$((now - pwr_win))
                [ "$age" -ge "$TAP_WINDOW_MS" ] && {
                    [ "$pwr_taps" -ge 1 ] && fire "power_long_tap${pwr_taps}"
                    pwr_taps=0; pwr_win=0; pwr_long=0
                }
            }
            return
        fi
        hold=$((pr - pp))
        # Upper bound: Kindle shows shutdown menu after ~10s hold.
        # Only handle power_long if released between PWR_LONG_MS and 9s.
        if [ "$hold" -ge "$PWR_LONG_MS" ] && [ "$hold" -lt 9000 ]; then
            fire "power_long"; pwr_long=1; pwr_taps=0; pwr_win=0
        elif [ "$pwr_long" = "1" ]; then
            pwr_taps=$((pwr_taps + 1))
            if [ "$pwr_taps" -ge "$MAX_TAPS" ]; then
                fire "power_long_tap${pwr_taps}"; pwr_taps=0; pwr_win=0; pwr_long=0
            else
                pwr_win=$(ms)
            fi
        fi
        pwr_last="$pr"
    }

    # bh/nh    : back/next currently held (1/0)
    # bt/nt    : timestamp of back/next press
    # cf       : combo is active (suppress solo events)
    # combo_base  : which button was pressed first ("back" | "next" | "")
    # combo_taps  : how many times the aux button was tapped while base is held
    bh=0; bt=0; nh=0; nt=0; cf=0; combo_base=""; combo_taps=0
    trap 'kill $(jobs -p) 2>/dev/null; rm -f ${T}_pp ${T}_pr' EXIT
    pwr_reader &

    while true; do
        [ -f "/tmp/kbh_paused" ] && { sleep 1; continue; }
        chk_pwr
        # timeout 1: loop cycles every ~1s so chk_pwr runs even with no page events
        ev=$(timeout 1 dd if="$DEV_PAGE" bs=16 count=1 2>/dev/null | hexdump -v -e '16/1 "%02X"')
        [ "${#ev}" -lt 28 ] && continue
        t="${ev:16:4}"; c="${ev:20:4}"; v="${ev:24:8}"
        [ "$t" = "0100" ] || continue

        if [ "$c" = "$BACK_CODE" ]; then
            if [ "$v" = "01000000" ]; then
                # BACK pressed
                if [ "$nh" = "1" ]; then
                    # next already held → back is an aux tap on next-as-base combo
                    combo_taps=$((combo_taps + 1)); cf=1
                else
                    bh=1; bt=$(ms)
                    [ "$cf" = "0" ] && { combo_base="back"; combo_taps=0; }
                fi
            else
                # BACK released
                bh=0
                if [ "$combo_base" = "back" ] && [ "$cf" = "1" ]; then
                    # back was base, fire with tap count
                    if [ "$combo_taps" -eq 1 ]; then fire "back_next_combo"
                    else fire "back_next_combo${combo_taps}"; fi
                    combo_base=""; combo_taps=0; cf=0
                elif [ "$combo_base" = "next" ] && [ "$nh" = "0" ]; then
                    # next was base and already fired on next-release; clean up
                    combo_base=""; cf=0
                elif [ "$cf" = "0" ] && [ "$bt" -gt 0 ]; then
                    e=$(($(ms) - bt))
                    [ "$e" -ge "$LONG_PRESS_MS" ] && fire "back_long" || fire "back_short"
                fi
                bt=0
            fi

        elif [ "$c" = "$NEXT_CODE" ]; then
            if [ "$v" = "01000000" ]; then
                # NEXT pressed
                if [ "$bh" = "1" ]; then
                    # back already held → next is an aux tap on back-as-base combo
                    combo_taps=$((combo_taps + 1)); cf=1
                else
                    nh=1; nt=$(ms)
                    [ "$cf" = "0" ] && { combo_base="next"; combo_taps=0; }
                fi
            else
                # NEXT released
                nh=0
                if [ "$combo_base" = "next" ] && [ "$cf" = "1" ]; then
                    # next was base, fire with tap count
                    if [ "$combo_taps" -eq 1 ]; then fire "next_back_combo"
                    else fire "next_back_combo${combo_taps}"; fi
                    combo_base=""; combo_taps=0; cf=0
                elif [ "$combo_base" = "back" ] && [ "$bh" = "0" ]; then
                    # back was base and already fired on back-release; clean up
                    combo_base=""; cf=0
                elif [ "$cf" = "0" ] && [ "$nt" -gt 0 ]; then
                    e=$(($(ms) - nt))
                    [ "$e" -ge "$LONG_PRESS_MS" ] && fire "next_long" || fire "next_short"
                fi
                nt=0
            fi
        fi
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
mkdir -p "$DATA/apps/global_defaults" "$DATA/apps/kindle_browser" 2>/dev/null || true

case "${1:-toggle}" in
    __daemon)  daemon_run ;;
    start)     start_d ;;
    stop)      stop_d ;;
    restart)   stop_d; sleep 1; start_d ;;
    status)    status ;;
    info)      info ;;
    menu)      ;;
    cap_power) cap_btn power ;;
    cap_next)  cap_btn next ;;
    cap_back)  cap_btn back ;;
    btn_power) show_btn power ;;
    btn_next)  show_btn next ;;
    btn_back)  show_btn back ;;
    toggle)
        if running; then stop_d; else start_d; fi
        ;;
esac
