#!/bin/sh

MESSAGE=$(cat)

# Maximum number of body lines to include in the notification
MAX_BODY_LINES=7

SUBJECT=$(printf '%s' "$MESSAGE" | grep -i '^Subject:' | head -1 | sed 's/^[Ss]ubject:[[:space:]]*//')
BODY=$(printf '%s' "$MESSAGE" | sed -n '/^$/,$ p' | sed '1d' | head -n "$MAX_BODY_LINES")

[ -z "$SUBJECT" ] && SUBJECT="Sendmail message"

if [ -z "$BODY" ]; then
    BODY==$(printf '%s' "$MESSAGE" | head -n "$MAX_BODY_LINES")
fi


# Find the DBUS session bus address from the running user session
USER_PID=$(pgrep -u antoniosalsi xfce4-session 2>/dev/null | head -1)
if [ -z "$USER_PID" ]; then
    USER_PID=$(pgrep -u antoniosalsi xfce4-notifyd 2>/dev/null | head -1)
fi

if [ -n "$USER_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$USER_PID/environ 2>/dev/null | tr '\0' '\n' | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)
fi

# Fallback to static path
if [ -z "$DBUS_ADDR" ]; then
    DBUS_ADDR="unix:path=/run/user/1000/bus"
fi



sudo -u antoniosalsi \
    DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
    notify-send -t 2500 "$SUBJECT" "$BODY" --icon=dialog-information -u normal

exit 0
