#!/usr/bin/env bash
set -euo pipefail

DURATION="${1:-20}"
CSV="/tmp/powertop-summary.csv"
BAT="/sys/class/power_supply/BAT1"

if [[ $EUID -ne 0 ]]; then
    exec sudo nix shell nixpkgs#powertop --command bash "$0" "$@"
fi

echo "Measuring for ${DURATION}s..."
powertop --csv="$CSV" --time="$DURATION" --iteration=1 >/dev/null 2>&1

# Total system power from battery
status=$(cat "$BAT/status")
if [[ "$status" == "Discharging" ]]; then
    current=$(cat "$BAT/current_now")
    voltage=$(cat "$BAT/voltage_now")
    total_w=$(awk "BEGIN {printf \"%.1f\", $current * $voltage / 1e12}")
    echo
    echo "=== Total System Power: ${total_w}W (${status}) ==="
else
    echo
    echo "=== Battery Status: ${status} (no power draw measurement) ==="
fi

extract_power() {
    local section_name="$1"
    local mode="$2"  # "device" or "software"
    local in_section=0

    while IFS= read -r line; do
        # Enter section when we find the header
        if [[ "$line" == *"$section_name"* ]]; then
            in_section=1
            continue
        fi

        # Stop at next section header
        if [[ $in_section -eq 1 && "$line" == *"*  *  *"* ]]; then
            break
        fi

        [[ $in_section -ne 1 ]] && continue
        [[ "$line" != *";"* ]] && continue

        # Extract power value from end of line: number + W or mW
        if [[ "$line" =~ ([0-9]+\.?[0-9]*)[[:space:]]*(mW|W)[[:space:]]*$ ]]; then
            local val="${BASH_REMATCH[1]}"
            local unit="${BASH_REMATCH[2]}"

            # skip zeros
            [[ "$val" == "0" || "$val" == "0.00" || "$val" == "0.0" ]] && continue

            local power="${val} ${unit}"

            # convert to watts for sorting
            local watts="$val"
            if [[ "$unit" == "mW" ]]; then
                watts=$(awk "BEGIN {printf \"%.6f\", $val / 1000}")
            fi

            # extract description
            local desc
            if [[ "$mode" == "device" ]]; then
                # Device name is between first ; and last ;
                # Handles names with semicolons (e.g., "Strix Data Fabric; Function 3")
                desc=$(echo "$line" | sed 's/^[^;]*;//; s/;[^;]*$//')
            else
                # Software: description is field 7
                desc=$(echo "$line" | cut -d';' -f7)
            fi
            desc=$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # clean up nix paths and PIDs
            desc=$(echo "$desc" | sed 's|/nix/store/[^/]*/||g; s/\[PID [0-9]*\] //')

            printf "%s\t%s\t%s\n" "$watts" "$power" "$desc"
        fi
    done < "$CSV"
}

# Package C-state residency
echo
echo "=== Package Idle States ==="
echo
in_pkg=0
got_data=0
while IFS= read -r line; do
    if [[ "$line" == *"Processor Idle State Report"* ]]; then
        in_pkg=1
        continue
    fi
    [[ $in_pkg -ne 1 ]] && continue
    # Skip blank lines and Package header before data
    [[ -z "$line" ]] && { [[ $got_data -eq 1 ]] && break || continue; }
    [[ "$line" == "Package;"* ]] && continue
    # Stop at separator lines after we've seen data
    if [[ "$line" == ";"* ]]; then
        [[ $got_data -eq 1 ]] && break || continue
    fi
    if [[ "$line" =~ ^([A-Z0-9]+)\;[[:space:]]*([0-9]+\.[0-9]+)% ]]; then
        printf "  %-6s %6s%%\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        got_data=1
    fi
done < "$CSV"

echo
echo "=== Device Power ==="
echo
printf "%-10s  %s\n" "Power" "Device"
printf "%-10s  %s\n" "-----" "------"
extract_power "Device Power Report" device | sort -t$'\t' -k1 -rn | while IFS=$'\t' read -r _ pw dev; do
    printf "%-10s  %s\n" "$pw" "$dev"
done

echo
echo "=== Top Software Consumers ==="
echo
printf "%-10s  %s\n" "Power" "Process"
printf "%-10s  %s\n" "-----" "-------"
extract_power "Overview of Software Power" software | sort -t$'\t' -k1 -rn | head -20 | while IFS=$'\t' read -r _ pw proc; do
    printf "%-10s  %s\n" "$pw" "$proc"
done

rm -f "$CSV"
