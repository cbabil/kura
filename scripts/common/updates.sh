#!/bin/bash
# scripts/common/updates.sh — what the device knows about updates, for the
# login screen (kura-issue) and the message after login (motd/10-status).
# Installed as /usr/lib/<brand>/updates.sh. Defines functions only.

# newer_version <package>: the repository's version when it differs from the
# one installed (apt's lists are refreshed daily; nothing is downloaded
# here). Nothing when up to date or when apt cannot say.
newer_version() {
    apt-cache policy "$1" 2>/dev/null | awk '
        $1 == "Installed:" { have = $2 }
        $1 == "Candidate:" { want = $2 }
        END { if (want != "" && want != "(none)" && have != "(none)" && want != have) print want }' || true
}
