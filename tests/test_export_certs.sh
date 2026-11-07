#!/bin/sh
# export_certs.php against link attacks (audit F01), as root in a throwaway container.
set -u
exec docker run --rm -v "$ROOT:/repo:ro" php:8.4-cli sh -c '
set -u
X=/repo/plugin/src/opnsense/scripts/OPNsense/Warpgate/export_certs.php
D=/usr/local/etc/warpgate/certs
groupadd -g 12345 warpgate && useradd -u 12345 -g warpgate -M -d /nonexistent warpgate
install -d -o root -g warpgate -m 0750 /usr/local/etc/warpgate $D   # as setup_dirs.sh
echo ROOT_OWNED > /tmp/victim && chmod 0600 /tmp/victim
export_certs() { REFS="$1" php -d include_path=/repo/tests/stubs "$X" 2>/dev/null; }
as_warpgate() { setpriv --reuid=12345 --regid=12345 --init-groups "$@"; }
fail=0
expect() { if eval "$1"; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }

expect "! as_warpgate ln -s /tmp/victim $D/a.key 2>/dev/null" "the service user cannot create links in certs/"
ln -s /tmp/victim $D/a.key   # worst case: a link there anyway
export_certs "{\"tls_certificate\":\"a\",\"http_sni_certificates\":\"s1,s2\"}"
expect "[ \"\$(cat /tmp/victim)\" = ROOT_OWNED ] && [ \"\$(stat -c %U%a /tmp/victim)\" = root600 ]" "a planted link does not redirect the write"
expect "[ \"\$(stat -c %F:%U:%G:%a $D/a.key)\" = \"regular file:root:warpgate:640\" ] && [ \"\$(cat $D/a.key)\" = KEY-a ]" "key written as root:warpgate 0640"
expect "[ -s $D/s1.pem ] && [ -s $D/s2.key ]" "SNI certificates (comma list) exported"
expect "as_warpgate cat $D/a.key >/dev/null && ! as_warpgate sh -c \"echo x >> $D/a.key\" 2>/dev/null" "the service can read but not write"
export_certs "{\"tls_certificate\":\"a\",\"http_certificate\":\"missing\"}"; rc=$?
expect "[ \$rc = 1 ] && [ \"\$(cat $D/a.key)\" = KEY-a ] && [ -s $D/s1.pem ]" "a missing certificate changes nothing"
touch $D/self-signed.pem $D/self-signed.key $D/.export-stale
export_certs "{\"rdp_certificate\":\"b\"}"
expect "[ \"\$(ls -A $D | tr \"\\n\" \" \")\" = \"b.key b.pem self-signed.key self-signed.pem \" ]" "unused and stale files removed, self-signed kept"
mv $D /tmp/real && ln -s /tmp/real $D
expect "! export_certs \"{\\\"tls_certificate\\\":\\\"a\\\"}\"" "refuses a certs/ that is a link"
rm $D && mv /tmp/real $D && chown warpgate $D
expect "! export_certs \"{\\\"tls_certificate\\\":\\\"a\\\"}\"" "refuses a certs/ not owned by root"
exit $fail'
