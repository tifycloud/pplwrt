# 首次 enrollment 清单

第一次启动断开 WAN，只保留一台管理员电脑直连隔离有线 LAN；不要通过 Wi-Fi、远程
跳板或生产交换网络首登。准备官方恢复/串口、稳定电源和离线证据盘。

1. 设置唯一随机 root 密码，核对 HTTPS 证书指纹；不要上传 `/etc/shadow`。
2. 运行：

   ```sh
   /usr/share/company/enrollment-preflight \
     --expected-version 25.12.5-company.2-rc2
   ```

   所有 FAIL 必须解决；WARN 也写入验收记录。
3. 人工核对 `ubus call system board` 是 `xiaomi,ax9000`、target 是
   `qualcommax/ipq807x`，再核对 `/etc/companywrt/build.conf` 和 VERSION。
4. 保留官方 LuCI 主题；检查 uhttpd redirect/listener、WAN firewall UCI 和实际 nft rules。
5. 逐个确认 DSA 端口、管理 IP、时区/NTP、监管域。先只启用 unicom，验证 IPv4/IPv6、
   DNS/NAT；再在维护窗口加入 mobile。
6. 用 `company-network plan` 生成并逐行审阅 UCI staging plan。不存在 live apply。
7. 最后配置 VLAN/WireGuard/log collector/monitoring/OpenClash；每项记录 mark/table/DNS/MTU
   所有权与回滚。mobile SQM 只能经安装模板和性能测试后启用，unicom 默认关闭。
8. 做离线配置/日志备份和恢复演练。没有 boot slot/救援/断电证据不能进行 OTA。

RC 通过 enrollment 不等于生产批准；stable 还需要 `production-gates` 全部真机证据。
