# CompanyWrt release verification keys

`companywrt-release.pub` is the current public `usign` trust anchor embedded in
RC2 and later images. Its fingerprint is:

```text
444eb53ba66e6d45
```

`companywrt-release-previous.pub` is the previous RC1 trust anchor:

```text
679439846de7ada5
```

RC2 is the explicit transition declared by `ROTATION.env`. Its primary
`RELEASE-MANIFEST.sig` is signed by the previous key so a stock RC1 device can
verify the upgrade without a public-key override. RC2 also carries
`RELEASE-MANIFEST.next.sig`, a current-key signature over the same manifest,
and embeds only the current public key. Releases after RC2 use the current key
as their primary manifest signer.

The current private key exists only as the `COMPANYWRT_USIGN_CURRENT_SECRET_KEY`
secret on the protected GitHub environment `firmware-signing`. The previous
private key remains temporarily available as the repository secret
`COMPANYWRT_USIGN_SECRET_KEY` only until the immutable RC2 transition release
and both signatures have been verified; it is deleted immediately afterward.
Neither private key may enter git, firmware, artifacts, logs, or release assets.

RC1 remains a prerelease with its historical old-key-signed assets intact for
audit. Do not rewrite RC1, silently replace either public key, or remove the
transition declaration without a separately reviewed future rotation plan.
