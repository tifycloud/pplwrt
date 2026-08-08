# CompanyWrt release verification key

`companywrt-release.pub` is the public `usign` key embedded into every image.
Its `usign -F -p` fingerprint is:

```text
679439846de7ada5
```

The matching private key is not stored in this repository, build artifacts,
logs or release assets. GitHub Actions receives it only from the encrypted
`COMPANYWRT_USIGN_SECRET_KEY` repository secret. A tag/release build fails
closed when that secret is missing or when its public fingerprint differs.

Key rotation requires a reviewed release that contains both old-key migration
instructions and the new public key before any later manifest is signed only
by the new key. Do not replace this file as an incidental build change.
