`packages.txt` is the auditable base package selection. It explicitly includes
usign, WireGuard, logd and the lean router runtime. collectd and the complete
OpenClash runtime dependency set are optional; `mwan3` is absent by design and
policy ownership stays with firewall4/nftables + pbr.

SQM is intentionally separate in `packages-sqm-optional.txt` because OpenWrt
25.12.5 pulls iptables compatibility dependencies. The review template applies
only to measured `mobile`; `unicom` stays disabled by default. A feed rename or
missing package fails the build instead of silently substituting a package.
