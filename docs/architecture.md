# Architecture

```
upstream tag ──make binary──▶ out/dist/warpgate-<tag>-x86_64-freebsd15.1 + .sig ──▶ GitHub Release warpgate-<tag>
plugin/ + that binary ──build-repo.sh (FreeBSD)──▶ signed pkg repo ──▶ GitHub Release repo-FreeBSD-15-amd64
                                                  landing page, warpgate.conf, warpgate.pub ──▶ gh-pages (Pages)

router: /usr/local/etc/pkg/repos/warpgate.{conf,pub} ──pkg──▶ os-warpgate (plugin + /usr/local/bin/warpgate)
```

## Binary build (`build/warpgate/`)

`build.sh <tag>` clones the upstream tag into `out/src/<tag>` and cross-compiles it for `x86_64-unknown-freebsd`
in Docker. There is no fork: same sources, same `Cargo.lock`, the toolchain pinned by upstream's `rust-toolchain.toml`,
`--all-features` like upstream CI, fat LTO like upstream's release profile. Only the target, a FreeBSD sysroot
(official `base.txz`, hash pinned in the `Dockerfile`) and the linker differ. The result is signed (`.sig`).

`patches/` holds FreeBSD fixes not yet upstream (currently 2 lines: a default data path in `setup.rs`).
They are applied automatically; a patch that stops applying fails the build. Goal: upstream them and delete the folder.
Because of the patch, `warpgate version` reports `<tag>-modified`.

OPNsense 26.7 is FreeBSD 15.1 (26.1 was 14.3). For another base, change `FREEBSD_VERSION` and `FREEBSD_BASE_SHA256`
in the `Dockerfile` (hash from that release's `MANIFEST`). Each sysroot gets its own cargo target dir.

A full build takes ~1 h (the final LTO link alone ~40 min and ~7.5 GB RAM); `out/cache` keeps the toolchain,
registry and npm cache between builds.

## Package (`build/repo/`)

`build-repo.sh SITE BINARY [KEY]` runs on FreeBSD/OPNsense. It verifies `BINARY.sig` against `build/signing.pub`,
puts the binary into the plugin as `/usr/local/bin/warpgate`, fetches OPNsense's plugin build system (`Mk/`,
`Scripts/`, `Templates/` from opnsense/plugins), runs `make package` and writes a flat `SITE/<ABI>/` with only the current
package and a catalogue signed by `pkg repo`. It also writes `warpgate.conf`, `warpgate.pub` and `index.html`.

Hosting: the repository (`SITE/<ABI>/`) is served from the release `repo-<ABI with : as ->` because GitHub Pages
deployments time out on the 27 MB package; release assets cannot be in subdirectories, hence the flat layout (no
`All/`). `pkg` follows the release download redirects. Pages only serves the small files. A new FreeBSD major
(another ABI) means another release tag and a new `warpgate.conf` on the routers.

Versioning: `PLUGIN_VERSION` = bundled Warpgate version, `PLUGIN_REVISION` for plugin-only changes
(`os-warpgate-0.30.4_1`). Any change to `plugin/` that should reach routers needs a version or revision bump,
otherwise `pkg` sees nothing new.

Package scripts: `+POST_INSTALL.post` restarts (upgrade) or starts (reinstall) the service when it is enabled;
`+PRE_DEINSTALL` stops it. The generic parts (configd restart, template reload, migrations, syslog reload) come from
OPNsense's plugin tooling.

## Plugin (`plugin/`)

Every option of Warpgate's config file is exposed (upstream `config-schema.json`), except the deprecated `ssh.keys`
and `recordings` sections: recordings (enable, disk or S3 storage) live in the database and are managed in the
Warpgate admin UI; the first start points them at `/var/db/warpgate/recordings`. Less common options are marked advanced (OPNsense's *advanced mode* toggle).

| Tab | Settings |
|---|---|
| General | enable, listen address, external host, TLS certificate (System: Trust or Warpgate's self-signed), log retention/format/forwarding, debug level; advanced: database URL, admin API token |
| HTTPS | port, reverse proxy (external port, trust `X-Forwarded-*`); advanced: external host, PROXY protocol, session/cookie lifetime, own certificate, SNI certificates |
| SSH | enable, port, target host key verification; advanced: timeouts, keepalive, external host/port, PROXY protocol |
| Protocols | MySQL, PostgreSQL, Kubernetes, VNC, RDP: enable, port; advanced: external host/port, PROXY protocol, own certificate, protocol extras |
| SSO | OpenID Connect providers (custom, Google, Entra ID, Apple) with role mappings, auto-created users, kubectl |
| Tools | Warpgate's own CLI: check config, SSH client keys, recover access, create user; advanced: copy database, run migrations |

| Piece | File(s) |
|---|---|
| model / forms (`settings.xml` with tabs, `dialogProvider.xml`) | `mvc/app/models/OPNsense/Warpgate/General.xml`, `controllers/OPNsense/Warpgate/forms/` |
| settings + SSO grid API (`/api/warpgate/general/*`), service API, tools API (`/api/warpgate/tools/*`) | `controllers/OPNsense/Warpgate/Api/` |
| page | `views/OPNsense/Warpgate/index.volt` |
| `/etc/rc.conf.d/warpgate` (enable, debug, admin token), `/usr/local/etc/warpgate.yaml` | `service/templates/OPNsense/Warpgate/` |
| CLI wrapper for the tools (validates input, runs as `warpgate`, drives interactive `recover-access` on a pty) | `scripts/OPNsense/Warpgate/wgctl.py` |
| export of System: Trust certificates to `/var/db/warpgate/certs/` (run before each start) | `scripts/OPNsense/Warpgate/export_certs.php` |
| own log `/var/log/warpgate/`, viewer at *Services → Warpgate → Log File* | `service/templates/OPNsense/Syslog/local/warpgate.conf` |
| remote syslog application, service registration | `etc/inc/plugins.inc.d/warpgate.inc` |
| service | `etc/rc.d/warpgate` |

The yaml template passes every string through `tojson` (a JSON string is a valid YAML scalar), so values cannot
break or inject configuration. Generated passwords (recover access, create user) never appear on a command line.

Runtime on the router:

- `/usr/local/bin/warpgate` (from the package), run by `daemon(8)` as user `warpgate` with `--skip-securing-files`
  (the rc script manages modes: config `0640 root:warpgate`, rc.conf.d `0600` because of the admin token)
- `/var/db/warpgate/`: sqlite database, self-signed TLS certificate/key, `certs/` (exported), `recordings/`,
  `initial-admin-password` until dismissed in the GUI; kept on uninstall, as are the `warpgate` user and the settings
- first start (no `.setup-done` marker and no `db/`) runs `warpgate unattended-setup`

Reverse proxy: set *External host*, *Behind a reverse proxy* and *External port* (usually 443); the proxy must talk
HTTPS to Warpgate. TCP proxies sending the PROXY protocol: enable it per listener. FreeBSD does not dual-stack `::`,
so the listen address defaults to `0.0.0.0`.
