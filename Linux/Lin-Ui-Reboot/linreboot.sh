#!/usr/bin/env bash

# Datto Linux post-patch reboot notification
# Run as root.
#
# Behaviour:
#   1. Checks whether a reboot is required.
#   2. Notifies logged-in graphical users.
#   3. Repeats the notification every 30 minutes.
#   4. Automatically reboots after 8 hours.
#
# Datto component variables can override these:
#   REBOOT_DELAY_HOURS=8
#   REMINDER_MINUTES=30
#   FORCE_REBOOT_ALWAYS=false

set -u
set -o pipefail

REBOOT_DELAY_HOURS="${REBOOT_DELAY_HOURS:-8}"
REMINDER_MINUTES="${REMINDER_MINUTES:-30}"
FORCE_REBOOT_ALWAYS="${FORCE_REBOOT_ALWAYS:-false}"

STATE_DIR="/var/lib/datto-patch-reboot"
NOTIFY_SCRIPT="/usr/local/sbin/datto-patch-reboot-notify"
DEADLINE_FILE="${STATE_DIR}/deadline"
LOG_FILE="/var/log/datto-patch-reboot.log"

REMINDER_UNIT="datto-patch-reboot-reminder"
FORCE_UNIT="datto-patch-force-reboot"

log()
{
    local message="$1"
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" |
        tee -a "$LOG_FILE"
}

is_positive_integer()
{
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

reboot_required()
{
    # Explicit override for environments where package-manager detection
    # is unavailable or where every patch run must end with a reboot window.
    case "${FORCE_REBOOT_ALWAYS,,}" in
        true|yes|1)
            log "FORCE_REBOOT_ALWAYS is enabled."
            return 0
            ;;
    esac

    # Debian, Ubuntu and related distributions.
    if [[ -f /run/reboot-required ||
          -f /var/run/reboot-required ]]; then
        log "Reboot-required marker file detected."
        return 0
    fi

    # RHEL, Rocky Linux, AlmaLinux, Oracle Linux, CentOS and Fedora.
    if command -v needs-restarting >/dev/null 2>&1; then
        needs-restarting -r >/dev/null 2>&1
        local result=$?

        # needs-restarting -r:
        #   0 = reboot not required
        #   1 = reboot required
        if [[ $result -eq 1 ]]; then
            log "needs-restarting reports that a reboot is required."
            return 0
        fi
    fi

    # Alternative kernel comparison for RPM-based systems where
    # needs-restarting is unavailable.
    if command -v rpm >/dev/null 2>&1 &&
       command -v uname >/dev/null 2>&1; then

        local running_kernel
        local newest_kernel

        running_kernel="$(uname -r)"

        newest_kernel="$(
            rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null |
                sort -V |
                tail -n 1
        )"

        if [[ -n "$newest_kernel" &&
              "$running_kernel" != "$newest_kernel" ]]; then
            log "Running kernel ${running_kernel}; newest installed kernel ${newest_kernel}."
            return 0
        fi
    fi

    return 1
}

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must run as root."
    exit 1
fi

if ! command -v systemd-run >/dev/null 2>&1; then
    log "ERROR: systemd-run is not available."
    exit 1
fi

if ! is_positive_integer "$REBOOT_DELAY_HOURS"; then
    log "ERROR: REBOOT_DELAY_HOURS must be a positive integer."
    exit 1
fi

if ! is_positive_integer "$REMINDER_MINUTES"; then
    log "ERROR: REMINDER_MINUTES must be a positive integer."
    exit 1
fi

if ! reboot_required; then
    log "No reboot is currently required. No reboot timer was created."
    exit 0
fi

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR"

DEADLINE_EPOCH="$(
    date -d "+${REBOOT_DELAY_HOURS} hours" '+%s'
)"

printf '%s\n' "$DEADLINE_EPOCH" > "$DEADLINE_FILE"
chmod 644 "$DEADLINE_FILE"

cat > "$NOTIFY_SCRIPT" <<'NOTIFY_SCRIPT_EOF'
#!/usr/bin/env bash

set -u
set -o pipefail

STATE_DIR="/var/lib/datto-patch-reboot"
DEADLINE_FILE="${STATE_DIR}/deadline"
LOG_FILE="/var/log/datto-patch-reboot.log"

log()
{
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

if [[ ! -r "$DEADLINE_FILE" ]]; then
    exit 0
fi

DEADLINE_EPOCH="$(cat "$DEADLINE_FILE" 2>/dev/null || true)"
NOW_EPOCH="$(date '+%s')"

if ! [[ "$DEADLINE_EPOCH" =~ ^[0-9]+$ ]]; then
    log "Invalid reboot deadline file."
    exit 1
fi

SECONDS_LEFT=$((DEADLINE_EPOCH - NOW_EPOCH))

if (( SECONDS_LEFT <= 0 )); then
    DISPLAY_TIME="now"
else
    HOURS_LEFT=$(((SECONDS_LEFT + 3599) / 3600))
    MINUTES_LEFT=$(((SECONDS_LEFT + 59) / 60))

    if (( HOURS_LEFT > 1 )); then
        DISPLAY_TIME="within ${HOURS_LEFT} hours"
    elif (( MINUTES_LEFT > 1 )); then
        DISPLAY_TIME="within ${MINUTES_LEFT} minutes"
    else
        DISPLAY_TIME="within 1 minute"
    fi
fi

MESSAGE="System updates have been installed.

A reboot is required to finish installing the updates.

Please save your work and reboot ${DISPLAY_TIME}.

The computer will reboot automatically when the deadline is reached."

notify_user()
{
    local user="$1"
    local uid="$2"
    local display="$3"
    local runtime_dir="/run/user/${uid}"
    local bus_address="unix:path=${runtime_dir}/bus"

    if [[ ! -d "$runtime_dir" ]]; then
        return
    fi

    # Zenity provides an actual Reboot now button.
    if command -v zenity >/dev/null 2>&1; then
        if runuser -u "$user" -- env \
            DISPLAY="$display" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="$bus_address" \
            zenity \
                --question \
                --title="Reboot required" \
                --text="$MESSAGE" \
                --ok-label="Reboot now" \
                --cancel-label="Later" \
                --width=480 \
                --timeout=300 2>/dev/null; then

            log "User ${user} selected Reboot now."
            systemctl reboot
            exit 0
        fi

        return
    fi

    # KDialog fallback for KDE desktops.
    if command -v kdialog >/dev/null 2>&1; then
        if runuser -u "$user" -- env \
            DISPLAY="$display" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="$bus_address" \
            kdialog \
                --title "Reboot required" \
                --warningyesno "$MESSAGE" \
                --yes-label "Reboot now" \
                --no-label "Later" 2>/dev/null; then

            log "User ${user} selected Reboot now."
            systemctl reboot
            exit 0
        fi

        return
    fi

    # Notification-only fallback.
    if command -v notify-send >/dev/null 2>&1; then
        runuser -u "$user" -- env \
            DISPLAY="$display" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="$bus_address" \
            notify-send \
                --urgency=critical \
                --expire-time=300000 \
                "Reboot required" \
                "$MESSAGE" 2>/dev/null || true

        return
    fi

    return 1
}

NOTIFIED=0

# Find active local graphical sessions.
while read -r session uid user seat tty; do
    [[ -n "$session" && -n "$uid" && -n "$user" ]] || continue

    session_type="$(
        loginctl show-session "$session" \
            --property=Type \
            --value 2>/dev/null
    )"

    session_active="$(
        loginctl show-session "$session" \
            --property=Active \
            --value 2>/dev/null
    )"

    session_display="$(
        loginctl show-session "$session" \
            --property=Display \
            --value 2>/dev/null
    )"

    [[ "$session_active" == "yes" ]] || continue
    [[ "$session_type" == "x11" || "$session_type" == "wayland" ]] || continue

    if [[ -z "$session_display" && "$session_type" == "x11" ]]; then
        session_display=":0"
    fi

    notify_user "$user" "$uid" "$session_display" && NOTIFIED=1

done < <(
    loginctl list-sessions \
        --no-legend \
        --no-pager 2>/dev/null
)

# Console fallback for servers or machines without a supported GUI utility.
if (( NOTIFIED == 0 )); then
    wall "$MESSAGE" 2>/dev/null || true
    log "No supported graphical notification session found; sent wall message."
else
    log "Reboot reminder displayed."
fi

exit 0
NOTIFY_SCRIPT_EOF

chmod 755 "$NOTIFY_SCRIPT"

# Replace an existing countdown if the component is run again.
systemctl stop "${REMINDER_UNIT}.timer" "${REMINDER_UNIT}.service" \
    "${FORCE_UNIT}.timer" "${FORCE_UNIT}.service" 2>/dev/null || true

systemctl reset-failed "${REMINDER_UNIT}.service" \
    "${FORCE_UNIT}.service" 2>/dev/null || true

# Reminder starts shortly after this component completes and repeats.
systemd-run \
    --unit="$REMINDER_UNIT" \
    --on-active="15 seconds" \
    --on-unit-active="${REMINDER_MINUTES} minutes" \
    --timer-property=AccuracySec=1s \
    "$NOTIFY_SCRIPT"

if [[ $? -ne 0 ]]; then
    log "ERROR: Could not create the reminder timer."
    exit 1
fi

# Separate one-shot forced reboot deadline.
systemd-run \
    --unit="$FORCE_UNIT" \
    --on-active="${REBOOT_DELAY_HOURS} hours" \
    --timer-property=AccuracySec=1min \
    /usr/bin/systemctl reboot

if [[ $? -ne 0 ]]; then
    log "ERROR: Could not create the forced reboot timer."
    systemctl stop "${REMINDER_UNIT}.timer" 2>/dev/null || true
    exit 1
fi

DEADLINE_READABLE="$(
    date -d "@${DEADLINE_EPOCH}" '+%Y-%m-%d %H:%M:%S %Z'
)"

log "Reboot is required."
log "Users will be reminded every ${REMINDER_MINUTES} minutes."
log "Automatic reboot scheduled for ${DEADLINE_READABLE}."

# Show the first popup immediately instead of waiting for the first timer.
"$NOTIFY_SCRIPT" || true

echo "SUCCESS: Reboot required."
echo "Automatic reboot deadline: ${DEADLINE_READABLE}"
echo "Reminder interval: ${REMINDER_MINUTES} minutes"

exit 0