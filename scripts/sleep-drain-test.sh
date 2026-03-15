#!/usr/bin/env bash
set -euo pipefail

BAT="/sys/class/power_supply/BAT1"
DATA_FILE="/tmp/sleep-drain-test.json"

usage() {
    echo "Usage: $0 {before|after}"
    echo
    echo "  before  Record battery state"
    echo "  after   Show battery drain results (run after waking)"
    exit 1
}

check_battery() {
    if [[ ! -d "$BAT" ]]; then
        echo "Error: $BAT not found"
        exit 1
    fi
}

cmd_before() {
    check_battery

    local capacity charge_now charge_full timestamp sleep_state
    capacity=$(cat "$BAT/capacity")
    charge_now=$(cat "$BAT/charge_now")
    charge_full=$(cat "$BAT/charge_full")
    timestamp=$(date +%s)
    sleep_state=$(cat /sys/power/mem_sleep | grep -oP '\[\K[^\]]+')

    cat > "$DATA_FILE" <<EOF
{
    "capacity": $capacity,
    "charge_now": $charge_now,
    "charge_full": $charge_full,
    "timestamp": $timestamp,
    "sleep_state": "$sleep_state"
}
EOF

    echo "Battery: ${capacity}%"
    echo "Charge:  $(awk "BEGIN {printf \"%.0f\", $charge_now / 1000}") / $(awk "BEGIN {printf \"%.0f\", $charge_full / 1000}") mAh"
    echo "Sleep:   $sleep_state"
    echo "Time:    $(date)"
    systemctl suspend
}

cmd_after() {
    check_battery

    if [[ ! -f "$DATA_FILE" ]]; then
        echo "Error: no 'before' data found. Run '$0 before' first."
        exit 1
    fi

    local capacity charge_now timestamp
    capacity=$(cat "$BAT/capacity")
    charge_now=$(cat "$BAT/charge_now")
    timestamp=$(date +%s)

    # Read before values
    local before_capacity before_charge before_charge_full before_ts sleep_state
    before_capacity=$(grep -oP '"capacity": \K[0-9]+' "$DATA_FILE")
    before_charge=$(grep -oP '"charge_now": \K[0-9]+' "$DATA_FILE")
    before_charge_full=$(grep -oP '"charge_full": \K[0-9]+' "$DATA_FILE")
    before_ts=$(grep -oP '"timestamp": \K[0-9]+' "$DATA_FILE")
    sleep_state=$(grep -oP '"sleep_state": "\K[^"]+' "$DATA_FILE")

    local elapsed_s elapsed_h charge_diff_uah drain_mah drain_pct_per_hr
    elapsed_s=$((timestamp - before_ts))
    elapsed_h=$(awk "BEGIN {printf \"%.2f\", $elapsed_s / 3600}")
    charge_diff_uah=$((before_charge - charge_now))
    drain_mah=$(awk "BEGIN {printf \"%.1f\", $charge_diff_uah / 1000}")
    drain_pct_per_hr=$(awk "BEGIN {printf \"%.2f\", $charge_diff_uah / $before_charge_full * 100 / ($elapsed_s / 3600)}")

    echo "=== Sleep Drain Test Results ==="
    echo
    echo "Sleep state: $sleep_state"
    echo "Duration:    ${elapsed_h}h ($(date -d@$before_ts '+%H:%M') -> $(date '+%H:%M'))"
    echo
    echo "  Before  -> After"
    echo "  $(awk "BEGIN {printf \"%.0f\", $before_charge / 1000}") mAh -> $(awk "BEGIN {printf \"%.0f\", $charge_now / 1000}") mAh  (${drain_mah} mAh used)"
    echo "  ${before_capacity}%      -> ${capacity}%"
    echo
    echo "Drain rate:  ${drain_pct_per_hr}%/hour  (${drain_mah} mAh/${elapsed_h}h)"

    # Estimate time to full drain from current charge
    local full_drain_h full_drain_days
    full_drain_h=$(awk "BEGIN {
        rate = $charge_diff_uah / ($elapsed_s / 3600);
        if (rate > 0) printf \"%.1f\", $charge_now / rate;
        else print \"inf\"
    }")
    full_drain_days=$(awk "BEGIN {
        if (\"$full_drain_h\" == \"inf\") print \"inf\";
        else printf \"%.1f\", $full_drain_h / 24
    }")
    echo "Time to empty: ${full_drain_h}h (~${full_drain_days} days) at this drain rate"
    echo

    # Check for deepest state issues
    if journalctl -b --no-pager 2>/dev/null | grep -q "didn't reach deepest state"; then
        echo "Sleep health: BAD - system did NOT reach deepest idle state"
        echo "  This means something prevented the CPU from entering its lowest power state."
        echo "  Common causes: USB devices, expansion cards, kernel bugs, firmware issues."
        echo "  Details: journalctl -b | grep 'deepest state'"
    else
        echo "Sleep health: GOOD - system reached deepest idle state"
    fi

    rm -f "$DATA_FILE"
}

case "${1:-}" in
    before) cmd_before ;;
    after)  cmd_after ;;
    *)      usage ;;
esac
