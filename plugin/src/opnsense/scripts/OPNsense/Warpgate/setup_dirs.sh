#!/bin/sh
# Create the warpgate user and the directories the plugin writes to (idempotent).
# Run as root by +POST_INSTALL (before templates are generated) and before every start.
#
# Everything root writes lives in root-owned directories, so the service account cannot redirect those
# writes with links. Templates get the mode of their directory (OPNsense's template engine copies it),
# and new files inherit the directory's group on FreeBSD:
#   /usr/local/etc/warpgate          root:warpgate 0750  warpgate.yaml -> 0640, readable by the service
#   /usr/local/etc/warpgate/certs    root:warpgate 0750  exported certificates and keys, 0640
#   /usr/local/etc/warpgate/private  root:wheel    0700  admin token env file, initial admin password, 0600
#   /var/db/warpgate                 warpgate      0700  the service's own data (database, recordings)
set -eu
ETC=/usr/local/etc/warpgate

pw groupshow warpgate >/dev/null 2>&1 || pw groupadd warpgate
pw usershow warpgate >/dev/null 2>&1 ||
    pw useradd warpgate -g warpgate -c "Warpgate bastion" -d /var/db/warpgate -s /usr/sbin/nologin

install -d -o warpgate -g warpgate -m 0700 /var/db/warpgate
install -d -o root -g warpgate -m 0750 "$ETC" "$ETC/certs"
install -d -o root -g wheel -m 0700 "$ETC/private"

# files generated before these directories had their final owner/mode
if [ -f "$ETC/warpgate.yaml" ]; then
    chown root:warpgate "$ETC/warpgate.yaml" && chmod 0640 "$ETC/warpgate.yaml"
fi
for f in "$ETC"/private/*; do
    [ -f "$f" ] && chown root:wheel "$f" && chmod 0600 "$f"
done

# leftovers of earlier versions: a world-readable config with secrets, files root wrote into the service's
# directory (rm does not follow a symlink operand)
rm -f /usr/local/etc/warpgate.yaml /var/db/warpgate/.setup-done
rm -rf /var/db/warpgate/certs
exit 0
