# Liquid theme upstream record

- Source: <https://github.com/zzsj0928/luci-theme-liquid>
- Vendored commit: `ad0cce67c02ce9ce0154c2f08491fc8ac1daf06b`
- Imported: 2026-08-09
- Upstream package version at import: `0.3-r18`

CompanyWrt changes are intentionally visible in this directory:

- brand the interface as “胖胖龙专用路由器” while retaining the ASCII system hostname;
- remove Bing wallpaper networking and its shell-based downloader;
- persist display preferences through a dedicated ACL-protected rpcd ucode method instead of a direct
  file-writing controller or the global LuCI pending-change queue;
- validate every server-rendered theme option before inserting it into HTML/CSS;
- integrate the CompanyWrt dashboard and first-run wizard surfaces;
- install a local copy of the applicable license and retain upstream attribution.

Upstream currently has a licensing inconsistency: the repository `LICENSE` file and GitHub license detection say
GPL-3.0, while its Makefile, README and individual headers say Apache-2.0. CompanyWrt uses the stricter
`GPL-3.0-only` package declaration and ships the upstream `LICENSE` verbatim. This is a conservative compliance
choice, not a claim that the upstream author intended to relicense any Apache-2.0 contribution.
