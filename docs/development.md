# Development

Everything is built in GitHub Actions ([releasing](releasing.md)): push to `main` and `publish-repo.yml` builds and
publishes the package. Locally there is only `make lint` (Docker), the same check CI runs on every push.

To try a change on a router before releasing it, copy `plugin/src` into its `/usr/local`, then
`service configd restart` and `rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json`.
The package artifact of each `publish-repo` run can also be installed with `pkg add`.

## Gotchas

- root's shell is csh: multi-line commands and `VAR=x cmd` break over ssh and under `su -m`.
- rc.subr handles `warpgate_user` itself (starts `daemon` as that user); do not add `daemon -u`.
- `make package` without `PLUGIN_DEVEL=` would produce `os-warpgate-devel`.
- Local logs need a template in `OPNsense/Syslog/local/`; `<plugin>_syslog()` only feeds the remote-logging list.
- `warpgate version` (there is no `--version`).
