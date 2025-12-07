#!/bin/bash

source "$CONFIG_DIR/colors.sh"

# Passed args: $1 = workspace_id being processed (mapped to item space.$1)
# Env vars usually available: $FOCUSED_WORKSPACE (from aerospace call)

SID=$1

if [ "$SID" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set $NAME background.drawing=on \
                         background.color=$COLOR_BASE02 \
                         label.color=$COLOR_BASE3 \
                         icon.color=$COLOR_BASE3
else
    sketchybar --set $NAME background.drawing=off \
                         label.color=$COLOR_BASE1 \
                         icon.color=$COLOR_BASE1
fi
