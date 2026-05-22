#!/bin/sh
# Kindle Button Handler [BETA]
# Entry point: status display, daemon control, button code wizard.
# Shown in Kindle library (only .sh file).
#
# Usage via KUAL:
#   button_main.sh             status screen
#   button_main.sh start|stop|restart
#   button_main.sh wizard [power|next|back|all]

SELF="$(cd "$(dirname "$0")" && pwd)"
DATA="/mnt/us/documents/button_handler"
PID="/tmp/kbh.pid"
HANDLER="$SELF/handler"

# ---------------------------------------------------------------------------
# Minimal eips UI (falls back to stdout when not on Kindle)
# ---------------------------------------------------------------------------
command -v eips >/dev/null 2>&1 || eips() { [ "$1" = "-c" ] && clear || echo "$*"; }

clr()      { eips -c; }
row()      { eips 0 "$1" "  $2"; }
hdr() {
    clr
    eips 0 0 "========================================"
    eips 0 1 "  $1"
    eips 0 2 "========================================"
}

# ---------------------------------------------------------------------------
# Daemon helpers
# ---------------------------------------------------------------------------
running() {
    local pid
    pid=$(cat "$PID" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

start_daemon() {
    if running; then
        row 5 "Already running (PID $(cat "$PID"))."; sleep 2; return
    fi
    if [ ! -f "$DATA/config" ]; then
        row 5 "No config. Run wizard first."; sleep 3; return
    fi
    "$HANDLER" >> /tmp/kbh.log 2>&1 &
    echo $! > "$PID"
    sleep 1
    if running; then
        row 5 "Started (PID $(cat "$PID"))."
    else
        row 5 "Failed to start. Check /tmp/kbh.log"
    fi
    sleep 2
}

stop_daemon() {
    if ! running; then
        row 5 "Not running."; rm -f "$PID"; sleep 2; return
    fi
    kill "$(cat "$PID")" 2>/dev/null
    rm -f "$PID"
    row 5 "Stopped."
    sleep 2
}

# ---------------------------------------------------------------------------
# Button code wizard
# ---------------------------------------------------------------------------

# Listen on all event devices for one key press.
# Prints "eventN:HEXCODE" or nothing on timeout.
_capture() {
    local cap="/tmp/kbh_cap$$"
    mkdir -p "$cap"
    local i=0 pids=""
    while [ "$i" -le 7 ]; do
        local dev="/dev/input/event$i"
        if [ -e "$dev" ]; then
            local n="$i"
            (
                while true; do
                    ev=$(dd if="$dev" bs=16 count=1 2>/dev/null | hexdump -v -e '16/1 "%02X"')
                    type="${ev:16:4}"; code="${ev:20:4}"; val="${ev:24:8}"
                    [ "$type" = "0100" ] && [ "$val" = "01000000" ] && [ "$code" != "0000" ] || continue
                    [ -f "$cap/r" ] && exit 0
                    printf "event%s:%s" "$n" "$code" > "$cap/r.tmp"
                    mv "$cap/r.tmp" "$cap/r" 2>/dev/null
                    exit 0
                done
            ) &
            pids="$pids $!"
        fi
        i=$((i + 1))
    done

    local t=12
    while [ "$t" -gt 0 ] && [ ! -f "$cap/r" ]; do
        eips 0 14 "  Listening... ${t}s   "
        sleep 1
        t=$((t - 1))
    done

    kill $pids 2>/dev/null
    wait 2>/dev/null
    [ -f "$cap/r" ] && cat "$cap/r"
    rm -rf "$cap"
}

wizard() {
    local target="${1:-all}"

    # Pause daemon so it doesn't consume events during capture
    running && kill -STOP "$(cat "$PID")" 2>/dev/null
    touch /tmp/kbh_paused

    # Load existing codes as fallback defaults
    [ -f "$DATA/config" ] && . "$DATA/config"
    pev="${BTN_POWER_EVENT:-event1}"; pcode="${BTN_POWER_CODE:-7400}"
    nev="${BTN_NEXT_EVENT:-event3}";  ncode="${BTN_NEXT_CODE:-6800}"
    bev="${BTN_BACK_EVENT:-event3}";  bcode="${BTN_BACK_CODE:-6D00}"

    hdr "BUTTON WIZARD [BETA]"
    row 4 "Press ONLY the button shown."
    row 5 "Wrong button = wrong code saved."
    row 7 "Starting in 5s..."
    sleep 5

    for btn in power next back; do
        [ "$target" != "all" ] && [ "$target" != "$btn" ] && continue
        case "$btn" in
            power) label="POWER" ;;
            next)  label="NEXT PAGE" ;;
            back)  label="PREV PAGE" ;;
        esac

        hdr "CAPTURE: $label"
        row 5 "Press and hold $label, then release."
        row 7 "!!! DO NOT press any other button !!!"

        result=$(_capture)

        if [ -n "$result" ]; then
            ev="${result%%:*}"; code="${result##*:}"
            case "$btn" in
                power) pev="$ev"; pcode="$code" ;;
                next)  nev="$ev"; ncode="$code" ;;
                back)  bev="$ev"; bcode="$code" ;;
            esac
            row 16 "Got: /dev/input/$ev  code 0x$code"
        else
            row 16 "Timeout — keeping previous value."
        fi
        sleep 3
    done

    # Save config (preserve timing values if already set)
    mkdir -p "$DATA"
    cat > "$DATA/config" << EOF
# Timing (ms)
LONG_PRESS_MS=${LONG_PRESS_MS:-800}
PWR_LONG_MS=${PWR_LONG_MS:-1000}
TAP_WINDOW_MS=${TAP_WINDOW_MS:-400}
MAX_TAPS=${MAX_TAPS:-3}

# Button event devices and key codes (little-endian hex from hexdump)
BTN_POWER_EVENT=$pev
BTN_POWER_CODE=$pcode
BTN_NEXT_EVENT=$nev
BTN_NEXT_CODE=$ncode
BTN_BACK_EVENT=$bev
BTN_BACK_CODE=$bcode
EOF

    hdr "WIZARD DONE"
    row 4 "Power:     /dev/input/$pev  0x$pcode"
    row 5 "Next:      /dev/input/$nev  0x$ncode"
    row 6 "Prev:      /dev/input/$bev  0x$bcode"
    row 8 "Saved to $DATA/config"
    sleep 4

    rm -f /tmp/kbh_paused
    running && kill -CONT "$(cat "$PID")" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Status screen
# ---------------------------------------------------------------------------
status() {
    hdr "KINDLE BUTTON HANDLER [BETA]"
    if running; then
        row 4 "Daemon:  RUNNING  (PID $(cat "$PID"))"
    else
        row 4 "Daemon:  STOPPED"
    fi
    if [ -f "$DATA/config" ]; then
        . "$DATA/config"
        row 6  "Power:   /dev/input/$BTN_POWER_EVENT  0x$BTN_POWER_CODE"
        row 7  "Next:    /dev/input/$BTN_NEXT_EVENT  0x$BTN_NEXT_CODE"
        row 8  "Prev:    /dev/input/$BTN_BACK_EVENT  0x$BTN_BACK_CODE"
        row 10 "Long press:   ${LONG_PRESS_MS}ms  |  Pwr long: ${PWR_LONG_MS}ms"
        row 11 "Tap window:   ${TAP_WINDOW_MS}ms  |  Max taps: ${MAX_TAPS}"
    else
        row 6 "No config — run wizard first."
    fi
    row 13 "Actions: $DATA/apps/<appname>/<gesture>"
    sleep 8
}

# ---------------------------------------------------------------------------
# Init & dispatch
# ---------------------------------------------------------------------------
mkdir -p "$DATA/apps/default" "$DATA/apps/kindle_browser"

# Auto-launch wizard on first run
if [ -z "$1" ] && [ ! -f "$DATA/config" ]; then
    hdr "FIRST RUN"
    row 5 "No config found. Starting wizard..."
    sleep 3
    wizard all
    exit 0
fi

case "${1:-status}" in
    start)   hdr "STARTING...";   start_daemon ;;
    stop)    hdr "STOPPING...";   stop_daemon  ;;
    restart) hdr "RESTARTING..."; stop_daemon; sleep 1; start_daemon ;;
    wizard)  wizard "${2:-all}"  ;;
    status|"") status ;;
    *) row 5 "Unknown: $1"; sleep 3 ;;
esac
