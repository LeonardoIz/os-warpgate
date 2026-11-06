# Signing

One RSA-4096 key signs both:

- every warpgate binary (`<binary>.sig`); `build-repo.sh` refuses to package a binary without a valid signature;
- the pkg repository catalogue (`pkg repo SITE KEY`), checked by `pkg` on the router.

The public key is `build/signing.pub`, published as `warpgate.pub` next to `warpgate.conf`; the router keeps it in
`/usr/local/etc/pkg/repos/warpgate.pub`. A catalogue signed with another key is rejected ("Invalid signature").

Fingerprint (SHA-256 of the DER public key):

    7f17a6885c0bc2d3f38c3dcab1d79446c948f171ad2f4fe840657b08057aa127

    openssl pkey -pubin -in /usr/local/etc/pkg/repos/warpgate.pub -outform DER | sha256     # on the router
    openssl pkey -pubin -in build/signing.pub -outform DER | sha256sum                       # here

## Key

    make genkey      # once; private key in keys/signing.key (git-ignored)

Store it as the GitHub secret `SIGNING_KEY` (`gh secret set SIGNING_KEY < keys/signing.key`), keep an offline
backup and delete the local copy. Losing it means a new key and fetching `warpgate.pub` again on every router.

## Rotating the key

`make genkey` refuses to overwrite. Move `keys/signing.key` away, run `make genkey`, update the secret, rebuild the
current binary release (`gh release delete warpgate-<tag>`, then run `build-warpgate.yml`); then fetch the new `warpgate.pub` on each router.
