# os-warpgate

OPNsense plugin (`os-warpgate`) for [Warpgate](https://github.com/warp-tech/warpgate), the smart SSH, HTTPS, MySQL,
PostgreSQL, Kubernetes, VNC and RDP bastion.

The package bundles upstream's release cross-compiled for FreeBSD (no fork; one small FreeBSD patch, see
[architecture](docs/architecture.md)), exposes all of Warpgate's settings in the OPNsense GUI, generates `warpgate.yaml`
from them and runs Warpgate as a service. Targets, users, roles and recordings are managed in Warpgate's own admin UI.

## Install on OPNsense

On the router, as root, add the repository (config + signing key):

    fetch -o /usr/local/etc/pkg/repos/ https://leonardoiz.github.io/os-warpgate/warpgate.conf https://leonardoiz.github.io/os-warpgate/warpgate.pub
    pkg update

Then install **os-warpgate** from *System → Firmware → Plugins*. It bundles the Warpgate binary; new Warpgate releases
arrive as normal plugin updates. To verify the key, see [signing](docs/signing.md).

In *Services → Warpgate → Settings*: enable, choose protocols (SSH, MySQL, PostgreSQL, Kubernetes, VNC, RDP) and ports,
reverse-proxy options if needed, *Apply*. The first start creates an `admin` user; its initial password is shown on
that page until you dismiss it. All of Warpgate's settings are there (certificates from System: Trust, SSO providers,
logging, …), plus a *Tools* tab for Warpgate's own commands (recover access, create user, SSH client keys,
database copy/migrations). Logs: *Services → Warpgate → Log File*. Open the Warpgate ports in the firewall as needed.

Uninstalling the plugin keeps Warpgate's data (`/var/db/warpgate`) and settings; reinstalling picks them up again.

## Repository

| Path | What |
|---|---|
| `Makefile` | entry point for everything: `make help` |
| `plugin/` | the plugin, same layout as [opnsense/plugins](https://github.com/opnsense/plugins) (`src/` installs into `/usr/local`) |
| `build/warpgate/` | Docker cross-build of upstream warpgate for FreeBSD, FreeBSD `patches/` |
| `build/repo/` | package + signed pkg repository (`build-repo.sh`, runs on FreeBSD), repo config and landing page |
| `build/genkey.sh`, `build/signing.pub` | signing key pair (private key in `keys/`) |
| `tests/` | behaviour tests (`make test`), also run by CI and before each Warpgate version bump |
| `docs/` | [architecture](docs/architecture.md), [development](docs/development.md), [signing](docs/signing.md), [releasing](docs/releasing.md) |
| `.github/workflows/` | lint and tests, warpgate builds, repository publishing |

Git-ignored: `keys/` (private signing key), `out/` (cache, upstream sources, binaries, built repository and site).

## License

Plugin: BSD 2-Clause (like OPNsense). Warpgate binaries: Apache-2.0, see `warpgate-LICENSE` in each release.
