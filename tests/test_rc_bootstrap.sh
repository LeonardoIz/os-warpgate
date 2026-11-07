#!/bin/sh
# rc.d/warpgate bootstrap with the real warpgate binary (audit F03/F04/F05): the admin user lands in the
# configured database, the SSH host key policy chosen in the GUI is applied, a failed first start is retried,
# later starts leave the database alone, and the stored initial password logs in.
# The real rc.d functions are loaded without rc.subr; su and logger are stubs.
# warn and the warpgate_* variables are used by the sourced rc.d functions; $4 is for the su stub
# shellcheck disable=SC2016,SC2034,SC2329
set -u
T=$(mktemp -d)
trap 'kill $(cat "$T/run.pid" 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/data" "$T/private" "$T/ext"
printf '#!/bin/sh\n# su -m USER -c CMD\nexec sh -c "$4"\n' > "$T/bin/su"
printf '#!/bin/sh\ncat >> "%s/logger.out"\n' "$T" > "$T/bin/logger"
chmod +x "$T/bin/su" "$T/bin/logger"
# free ports, so the test never talks to something else listening on a fixed one
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
HTTP_PORT=$(free_port)
SSH_PORT=$(free_port)
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 1 -subj /CN=t \
    -keyout "$T/k.pem" -out "$T/c.pem" >/dev/null 2>&1
cat > "$T/w.yaml" <<EOF
database_url: "sqlite:$T/ext/db"
http:
  listen: "127.0.0.1:$HTTP_PORT"
  certificate: "$T/c.pem"
  key: "$T/k.pem"
ssh:
  enable: true
  listen: "127.0.0.1:$SSH_PORT"
  host_key_verification: auto_reject
EOF
sed -e '/^\. \/etc\/rc.subr/d' -e '/^load_rc_config/d' -e '/^run_rc_command/d' "$ROOT/plugin/src/etc/rc.d/warpgate" > "$T/fns.sh"

PATH=$T/bin:$PATH
warn() { echo "   (warn: $*)"; }
# shellcheck disable=SC1091
. "$T/fns.sh"
warpgate_bin=$WG
warpgate_config=$T/w.yaml
warpgate_data=$T/data
pwfile=$T/private/initial-admin-password
warpgate_cli="${warpgate_bin} --skip-securing-files --config ${warpgate_config}"

fail=0
expect() { if eval "$1"; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
query() { python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchall())" "$T/ext/db/db.sqlite3" "$1"; }

chmod 0500 "$T/ext"
warpgate_bootstrap >/dev/null; rc=$?
expect '[ "$rc" != 0 ] && [ ! -e "$pwfile" ] && [ -s "$T/logger.out" ]' 'failed bootstrap: error logged, no password stored'
chmod 0700 "$T/ext"
expect 'warpgate_bootstrap >/dev/null && [ -s "$pwfile" ]' 'retry initialises the database and stores the password'
password=$(cat "$pwfile")
expect 'warpgate_bootstrap >/dev/null && [ "$(cat "$pwfile")" = "$password" ]' 'next start: database left alone, password kept'
expect '[ "$(query "select username from users")" = "[('"'"'admin'"'"',)]" ]' 'admin user is in the configured database'
expect '[ "$(query "select ssh_host_key_verification from parameters")" = "[('"'"'AutoReject'"'"',)]" ]' 'SSH host key policy from the config is applied'
expect '[ -z "$(ls "$T/data")" ]' 'the default data directory is untouched'

"$WG" --skip-securing-files --config "$T/w.yaml" run >/dev/null 2>&1 &
echo $! > "$T/run.pid"
for _ in $(seq 1 60); do curl -sk -o /dev/null "https://127.0.0.1:$HTTP_PORT/" && break; sleep 0.5; done
login() { curl -sk -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"$1\"}" "https://127.0.0.1:$HTTP_PORT/@warpgate/api/auth/login"; }
expect '[ "$(login "$password")" = 201 ] && [ "$(login wrong)" = 401 ]' 'the stored initial password logs in as admin'
exit $fail
