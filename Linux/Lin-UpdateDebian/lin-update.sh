#!/bin/bash

set -o pipefail

LOG_FILE="/var/log/datto-linux-upgrade.log"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

fail() {
    log "ERROR: $*"
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    fail "This component must run as root."
fi

if ! command -v apt-get >/dev/null 2>&1; then
    fail "APT was not found. This component supports Debian/Ubuntu-based systems only."
fi

log "Starting Linux package maintenance."

# Wait if another APT or DPKG process is currently running
WAIT_SECONDS=0
MAX_WAIT_SECONDS=900

while fuser /var/lib/dpkg/lock-frontend \
            /var/lib/dpkg/lock \
            /var/cache/apt/archives/lock \
            /var/lib/apt/lists/lock >/dev/null 2>&1; do

    if [ "$WAIT_SECONDS" -ge "$MAX_WAIT_SECONDS" ]; then
        fail "APT remained locked for more than 15 minutes."
    fi

    log "Another package operation is running. Waiting..."
    sleep 30
    WAIT_SECONDS=$((WAIT_SECONDS + 30))
done

log "Updating package lists."
apt-get update -y >>"$LOG_FILE" 2>&1 ||
    fail "apt-get update failed."

log "Installing available APT upgrades."
apt-get \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade -y >>"$LOG_FILE" 2>&1 ||
    fail "apt-get full-upgrade failed."

log "Removing unused APT packages."
apt-get autoremove -y >>"$LOG_FILE" 2>&1 ||
    fail "apt-get autoremove failed."

log "Cleaning APT package cache."
apt-get clean >>"$LOG_FILE" 2>&1 ||
    fail "apt-get clean failed."

# Update Flatpak applications and runtimes
if command -v flatpak >/dev/null 2>&1; then
    log "Flatpak detected."

    log "Updating system-wide Flatpak applications and runtimes."
    flatpak update \
        --system \
        --noninteractive \
        -y >>"$LOG_FILE" 2>&1

    SYSTEM_FLATPAK_EXIT=$?

    if [ "$SYSTEM_FLATPAK_EXIT" -ne 0 ]; then
        log "WARNING: System-wide Flatpak update returned exit code $SYSTEM_FLATPAK_EXIT."
    fi

    log "Removing unused system-wide Flatpak runtimes."
    flatpak uninstall \
        --system \
        --unused \
        --noninteractive \
        -y >>"$LOG_FILE" 2>&1

    SYSTEM_FLATPAK_CLEANUP_EXIT=$?

    if [ "$SYSTEM_FLATPAK_CLEANUP_EXIT" -ne 0 ]; then
        log "WARNING: System-wide Flatpak cleanup returned exit code $SYSTEM_FLATPAK_CLEANUP_EXIT."
    fi

    # Update Flatpaks installed for normal local users
    while IFS=: read -r username _ uid _ _ home shell; do
        if [ "$uid" -ge 1000 ] &&
           [ "$uid" -lt 65534 ] &&
           [ -d "$home" ] &&
           [[ "$shell" != *"nologin"* ]] &&
           [[ "$shell" != *"/false"* ]]; then

            log "Checking user Flatpaks for: $username"

            runuser -u "$username" -- \
                flatpak update \
                --user \
                --noninteractive \
                -y >>"$LOG_FILE" 2>&1

            USER_FLATPAK_EXIT=$?

            if [ "$USER_FLATPAK_EXIT" -ne 0 ]; then
                log "WARNING: Flatpak update for $username returned exit code $USER_FLATPAK_EXIT."
            fi

            runuser -u "$username" -- \
                flatpak uninstall \
                --user \
                --unused \
                --noninteractive \
                -y >>"$LOG_FILE" 2>&1

            USER_FLATPAK_CLEANUP_EXIT=$?

            if [ "$USER_FLATPAK_CLEANUP_EXIT" -ne 0 ]; then
                log "WARNING: Flatpak cleanup for $username returned exit code $USER_FLATPAK_CLEANUP_EXIT."
            fi
        fi
    done < /etc/passwd
else
    log "Flatpak is not installed. Skipping Flatpak updates."
fi

# Check for remaining APT updates
REMAINING_APT_UPDATES=$(
    apt-get -s full-upgrade 2>/dev/null |
    awk '/^Inst / {count++} END {print count+0}'
)

# Check for remaining system Flatpak updates
REMAINING_SYSTEM_FLATPAKS=0

if command -v flatpak >/dev/null 2>&1; then
    REMAINING_SYSTEM_FLATPAKS=$(
        flatpak remote-ls --system --updates 2>/dev/null |
        awk 'NF {count++} END {print count+0}'
    )
fi

log "Remaining APT updates: $REMAINING_APT_UPDATES"
log "Remaining system Flatpak updates: $REMAINING_SYSTEM_FLATPAKS"

echo "<-Start Result->"
echo "Linux package maintenance completed."
echo "Remaining APT updates: $REMAINING_APT_UPDATES"
echo "Remaining system Flatpak updates: $REMAINING_SYSTEM_FLATPAKS"

if [ -f /var/run/reboot-required ]; then
    log "SUCCESS: Package maintenance completed. A reboot is required."
    echo "Reboot required: Yes"

    if [ -f /var/run/reboot-required.pkgs ]; then
        echo "Packages requesting reboot:"
        cat /var/run/reboot-required.pkgs
    fi
else
    log "SUCCESS: Package maintenance completed. No reboot is required."
    echo "Reboot required: No"
fi

echo "<-End Result->"

exit 0