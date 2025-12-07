#!/bin/bash

VOLUME=$(osascript -e "output volume of (get volume settings)")
MUTED=$(osascript -e "output muted of (get volume settings)")

if [[ $MUTED != "false" ]]; then
  ICON=""
else
  case ${VOLUME} in
    100) ICON="" ;;
    [5-9][0-9]) ICON="" ;;
    [1-4][0-9]) ICON="" ;;
    [0-9]) ICON="" ;;
    *) ICON="" ;;
  esac
fi

sketchybar --set $NAME icon="$ICON" label="$VOLUME%"
