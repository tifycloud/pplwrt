'use strict';
'require view';
'require rpc';
'require uci';

var callSystemInfo = rpc.declare({ object: 'system', method: 'info', expect: {} });
var callSystemBoard = rpc.declare({ object: 'system', method: 'board', expect: {} });
var callInterfaces = rpc.declare({ object: 'network.interface', method: 'dump', expect: { interface: [] } });
var callDHCPLeases = rpc.declare({ object: 'luci-rpc', method: 'getDHCPLeases', expect: {} });

function bytes(value) {
	var number = Number(value || 0), units = ['B', 'KiB', 'MiB', 'GiB'], index = 0;
	while (number >= 1024 && index < units.length - 1) { number /= 1024; index++; }
	return '%s %s'.format(index > 1 ? number.toFixed(1) : Math.round(number), units[index]);
}

function duration(value) {
	var seconds = Number(value || 0), days = Math.floor(seconds / 86400), hours = Math.floor((seconds % 86400) / 3600);
	if (days > 0) return '%d 天 %d 小时'.format(days, hours);
	return '%d 小时 %d 分钟'.format(hours, Math.floor((seconds % 3600) / 60));
}

function interfaceByName(interfaces, name) {
	for (var i = 0; i < interfaces.length; i++) if (interfaces[i].interface === name) return interfaces[i];
	return null;
}

function activeClientCount(leases) {
	var clients = {};
	(leases.dhcp_leases || []).forEach(function(lease) {
		if (lease.macaddr) clients[lease.macaddr.toLowerCase()] = true;
	});
	(leases.dhcp6_leases || []).forEach(function(lease) {
		var key = lease.macaddr || lease.duid;
		if (key) clients[key.toLowerCase()] = true;
	});
	return Object.keys(clients).length;
}

function action(label, path, detail) {
	return E('a', { href: L.url.apply(L, path) }, [ E('strong', {}, label), E('small', {}, detail) ]);
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('company'), uci.load('network'), uci.load('wireless'), uci.load('firewall'), uci.load('pbr'),
			callSystemInfo(), callSystemBoard(), callInterfaces(), callDHCPLeases()
		]);
	},

	render: function(data) {
		if (uci.get('company', 'main', 'setup_complete') !== '1') {
			window.location.replace(L.url('admin', 'company', 'setup'));
			return E('div', { class: 'cw-page' }, E('p', {}, '正在打开首次设置…'));
		}

		var info = data[5] || {}, board = data[6] || {}, interfaces = data[7] || [], leases = data[8] || {};
		var memory = info.memory || {}, total = Number(memory.total || 0), available = Number(memory.available || 0);
		var used = Math.max(0, total - available), availablePercent = total ? Math.round(available * 100 / total) : 0;
		var wan = interfaceByName(interfaces, 'wan'), wan6 = interfaceByName(interfaces, 'wan6');
		var proto = uci.get('network', 'wan', 'proto') || '未配置';
		var pbrEnabled = uci.get('pbr', 'config', 'enabled') === '1';
		var clientCount = activeClientCount(leases);
		var wifiEnabled = 0, wifiTotal = 0;
		uci.sections('wireless', 'wifi-iface', function(section) {
			if (section.mode === 'ap') { wifiTotal++; if (section.disabled !== '1') wifiEnabled++; }
		});

		return E('div', { class: 'cw-page' }, [
			E('section', { class: 'cw-hero' }, [
				E('p', { class: 'cw-eyebrow' }, 'AX9000 · 网络控制中心'),
				E('h1', {}, '早上好，网络状态一眼看清'),
				E('p', {}, '先处理联网和无线，再进入 VLAN、PBR 与远程管理。这里显示实际可用内存，不把可回收缓存算成应用占用。'),
				E('div', { class: 'cw-actions' }, [
					E('a', { class: 'cw-action', href: L.url('admin', 'company', 'setup') }, '重新运行设置向导'),
					E('a', { class: 'cw-action secondary', href: L.url('admin', 'network', 'network') }, '管理网络接口')
				])
			]),
			E('div', { class: 'cw-stat-grid' }, [
				E('div', { class: 'cw-stat' }, [ E('span', {}, '可用内存'), E('strong', {}, '%d%%'.format(availablePercent)), E('small', {}, '%s 可立即分配'.format(bytes(available))) ]),
				E('div', { class: 'cw-stat' }, [ E('span', {}, '在线终端'), E('strong', {}, '%d 台'.format(clientCount)), E('small', {}, '按有效 DHCP 租约去重') ]),
				E('div', { class: 'cw-stat' }, [ E('span', {}, '连续运行'), E('strong', {}, duration(info.uptime)), E('small', {}, board.hostname || 'CompanyWrt') ])
			]),
			E('div', { class: 'cw-grid' }, [
				E('section', { class: 'cw-panel' }, [
					E('span', { class: wan && wan.up ? 'cw-badge' : 'cw-badge warn' }, wan && wan.up ? '互联网已连接' : '互联网未连接'),
					E('h2', {}, '现在要做什么'),
					E('p', {}, '常用操作放在这里，不需要先理解 OpenWrt 的全部菜单。'),
					E('div', { class: 'cw-quick' }, [
						action('设置宽带账号', ['admin', 'company', 'setup'], proto === 'pppoe' ? '当前使用 PPPoE' : 'PPPoE / DHCP'),
						action('设置 Wi‑Fi', ['admin', 'network', 'wireless'], '%d / %d 个接入点已启用'.format(wifiEnabled, wifiTotal)),
						action('双 WAN 与 PBR', ['admin', 'services', 'pbr'], pbrEnabled ? '配置已启用，仍需验证' : '尚未启用'),
						action('备份与升级', ['admin', 'system', 'flash'], '先备份，再进行变更')
					])
				]),
				E('aside', { class: 'cw-panel' }, [
					E('h3', {}, '运行摘要'),
					E('ul', { class: 'cw-status-list' }, [
						E('li', {}, [ E('span', {}, '设备'), E('strong', {}, board.model || 'Xiaomi AX9000') ]),
						E('li', {}, [ E('span', {}, '不可回收占用'), E('strong', {}, '%s / %s'.format(bytes(used), bytes(total))) ]),
						E('li', {}, [ E('span', {}, 'WAN 协议'), E('strong', {}, proto.toUpperCase()) ]),
						E('li', {}, [ E('span', {}, 'WAN 状态'), E('strong', {}, wan && wan.up ? '在线' : '离线') ]),
						E('li', {}, [ E('span', {}, 'IPv6'), E('strong', {}, wan6 && wan6.up ? '在线' : '未连接') ]),
						E('li', {}, [ E('span', {}, '无线接入点'), E('strong', {}, '%d 个已启用'.format(wifiEnabled)) ]),
						E('li', {}, [ E('span', {}, 'OpenClash'), E('strong', {}, '未预装 · 按需安装') ])
					]),
					E('div', { class: 'cw-actions' }, [ E('a', { class: 'cw-action light', href: L.url('admin', 'status', 'overview') }, '查看详细状态') ])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
