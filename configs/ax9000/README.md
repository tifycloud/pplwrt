`packages.txt` is intentionally a reviewable list. `mwan3` is absent by
design: choose policies with firewall4/nftables + pbr. If your release's feeds
rename a package, CI fails rather than silently selecting a different package.
