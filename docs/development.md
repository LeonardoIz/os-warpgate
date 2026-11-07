# Development

Everything is built in GitHub Actions ([releasing](releasing.md)): push to `main` and `publish-repo.yml` builds and
publishes the package. Locally there are the same two checks CI runs on every push:

    make lint      # shellcheck, php -l, python syntax, XML (Docker)
    make test      # behaviour tests (Docker, python3 + jinja2/jsonschema/pyyaml, openssl, gh, curl)

`make test` downloads into `out/test/` the OPNsense core it targets (pinned in `tests/run.sh`), the upstream Linux
build of the bundled Warpgate version (verified against GitHub's digest) and its config schema. It checks the file
modes and secret placement of the generated config with OPNsense's template engine, `warpgate check` on it, the
duration mask against warpgate, the certificate exporter against link attacks (as root in a container), the model's
validation with OPNsense's MVC framework, the rc.d bootstrap against a real warpgate, and wgctl.py's safeguards.
`build-warpgate.yml` runs it against every new upstream version before bumping the plugin.

To try a change on a router before releasing it, copy `plugin/src` into its `/usr/local`, then
`service configd restart` and `rm -f /tmp/opnsense_menu_cache.xml /tmp/opnsense_acl_cache.json`.
The package artifact of each `publish-repo` run can also be installed with `pkg add`.

## Gotchas

- root's shell is csh: multi-line commands and `VAR=x cmd` break over ssh and under `su -m`.
- rc.subr handles `warpgate_user` itself (starts `daemon` as that user); do not add `daemon -u`.
- `make package` without `PLUGIN_DEVEL=` would produce `os-warpgate-devel`.
- Local logs need a template in `OPNsense/Syslog/local/`; `<plugin>_syslog()` only feeds the remote-logging list.
- `warpgate version` (there is no `--version`).
