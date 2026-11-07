# Releasing

## Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | push / PR | `make lint`, `make test` |
| `build-warpgate.yml` | daily + manual (tag input) | for the latest upstream release: `make binary` and a signed release if missing; then, if that release is signed and newer than `PLUGIN_VERSION`, check upstream's bootstrap log line, `make test` against it, bump `PLUGIN_VERSION` (rebased on `main`) and run `publish-repo`. Each phase is retried by the next run until done |
| `publish-repo.yml` | push to `main` touching `plugin/` or `build/repo/`, manual | builds `os-warpgate` with the binary of `PLUGIN_VERSION` on FreeBSD 15.1, uploads the repository to the release `repo-FreeBSD-15-amd64` (keeps the previous package for routers with a cached catalogue) and force-publishes `gh-pages` (single commit) |

With the `SIGNING_KEY` secret everything is automatic: a new upstream Warpgate release reaches routers as a normal
plugin update within a day. Without it, binary releases stay drafts and nothing is published.

One-time setup: secret `SIGNING_KEY` (see [signing](signing.md)); *Settings → Pages* deploys from branch `gh-pages`.

## New Warpgate release

Automatic within a day, or right away: `gh workflow run build-warpgate.yml -f tag=v0.31.0`
(builds ~1 h, then publishes).

## Plugin-only change

Bump `PLUGIN_REVISION` in `plugin/Makefile` (or `PLUGIN_VERSION` with a new Warpgate) in the same commit, push to
`main`. Without a bump routers see no update.
