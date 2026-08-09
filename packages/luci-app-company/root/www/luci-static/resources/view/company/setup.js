'use strict';
'require view';
'require dom';
'require ui';
'require rpc';
'require uci';

var callSetPassword = rpc.declare({
	object: 'luci', method: 'setPassword', params: [ 'username', 'password' ], expect: { result: false }
});

function field(id, label, type, value, help, attributes) {
	var inputAttributes = Object.assign({ id: id, type: type, value: value || '', autocomplete: 'off' }, attributes || {});
	return E('div', { class: 'cw-field' }, [
		E('label', { for: id }, label),
		E('input', inputAttributes),
		help ? E('small', {}, help) : null
	]);
}

function choice(name, value, title, help, checked) {
	return E('label', { class: 'cw-choice' }, [
		E('input', { type: 'radio', name: name, value: value, checked: checked ? '' : null }),
		E('span', {}, [ E('strong', {}, title), E('small', {}, help) ])
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ uci.load('company'), uci.load('network'), uci.load('wireless') ]);
	},

	render: function() {
		var self = this;
		this.step = 0;
		this.state = {
			mode: uci.get('network', 'wan', 'proto') === 'pppoe' ? 'pppoe' : 'dhcp',
			username: uci.get('network', 'wan', 'username') || '',
			wanPassword: '',
			enableWifi: true,
			ssid: '胖胖龙',
			wifiPassword: '',
			adminPassword: '',
			adminConfirm: ''
		};

		this.body = E('div', { class: 'cw-wizard-card' });
		this.progress = E('div', { class: 'cw-steps', 'aria-label': '设置进度' });
		this.root = E('div', { class: 'cw-wizard' }, [
			E('header', { class: 'cw-wizard-head' }, [
				E('p', { class: 'cw-eyebrow' }, '胖胖龙专用路由器 · 首次设置'),
				E('h1', {}, '用 3 步完成基础联网'),
				E('p', {}, '先选上网方式，再设置 Wi‑Fi 和管理员密码。所有密码只保存在这台路由器中。'),
				this.progress
			]),
			this.body
		]);
		this.renderStep();
		return this.root;
	},

	showError: function(message) {
		var box = this.body.querySelector('.cw-error');
		if (box) { box.textContent = message; box.classList.add('visible'); box.scrollIntoView({ block: 'center' }); }
	},

	capture: function() {
		var value = function(id) { var node = document.getElementById(id); return node ? node.value.trim() : ''; };
		if (this.step === 0) {
			var selected = this.body.querySelector('input[name="cw-wan-mode"]:checked');
			this.state.mode = selected ? selected.value : 'dhcp';
			this.state.username = value('cw-pppoe-user');
			this.state.wanPassword = value('cw-pppoe-pass');
		}
		else if (this.step === 1) {
			var enabled = document.getElementById('cw-wifi-enable');
			this.state.enableWifi = enabled ? enabled.checked : false;
			this.state.ssid = value('cw-wifi-ssid');
			this.state.wifiPassword = value('cw-wifi-pass');
		}
		else if (this.step === 2) {
			this.state.adminPassword = value('cw-admin-pass');
			this.state.adminConfirm = value('cw-admin-confirm');
		}
	},

	validate: function() {
		if (this.step === 0 && this.state.mode === 'pppoe') {
			if (!this.state.username) return 'PPPoE 模式必须填写宽带账号。';
			if (!this.state.wanPassword && !uci.get('network', 'wan', 'password')) return 'PPPoE 模式必须填写宽带密码。';
		}
		if (this.step === 1 && this.state.enableWifi) {
			if (this.state.ssid.length < 1 || this.state.ssid.length > 32) return 'Wi‑Fi 名称必须为 1–32 个字符。';
			if (!this.state.wifiPassword && !this.existingWifiPassword()) return '启用 Wi‑Fi 时必须填写无线密码。';
			if (this.state.wifiPassword && this.state.wifiPassword.length < 8) return 'Wi‑Fi 密码至少需要 8 个字符。';
		}
		if (this.step === 2) {
			if (this.state.adminPassword.length < 10) return '管理员密码至少需要 10 个字符。';
			if (this.state.adminPassword !== this.state.adminConfirm) return '两次输入的管理员密码不一致。';
		}
		return null;
	},

	existingWifiPassword: function() {
		var found = '';
		uci.sections('wireless', 'wifi-iface', function(section) {
			if (!found && section.mode === 'ap' && section.key) found = section.key;
		});
		return found;
	},

	next: function() {
		this.capture();
		var error = this.validate();
		if (error) return this.showError(error);
		if (this.step < 2) { this.step++; this.renderStep(); window.scrollTo({ top: 0, behavior: 'smooth' }); }
		else this.applySettings();
	},

	back: function() {
		this.capture();
		if (this.step > 0) { this.step--; this.renderStep(); }
		else window.location.href = L.url('admin', 'company');
	},

	renderStep: function() {
		var self = this, content = [], title = '', description = '';
		var stepLabels = [ '宽带', 'Wi‑Fi', '管理' ];
		dom.content(this.progress, stepLabels.map(function(label, index) {
			return E('span', { class: index <= self.step ? 'cw-step active' : 'cw-step' }, [
				E('b', {}, String(index + 1)), E('small', {}, label)
			]);
		}));

		if (this.step === 0) {
			title = '设置主宽带'; description = '直接选择你的上网方式。保存之前不会修改网络。';
			content = [
				E('div', { class: 'cw-notice' }, [
					E('strong', {}, '保持网线连接'),
					E('p', {}, '建议先只连接管理电脑和 LAN；向导完成后再接联通 WAN。这个提示不会阻止你继续。')
				]),
				E('div', { class: 'cw-choice-grid' }, [
					choice('cw-wan-mode', 'pppoe', 'PPPoE 宽带拨号', '光猫桥接：填写运营商提供的宽带账号和密码。', this.state.mode === 'pppoe'),
					choice('cw-wan-mode', 'dhcp', 'DHCP 自动获取', '光猫或上级路由器已经拨号：无需填写账号。', this.state.mode === 'dhcp')
				]),
				E('div', { id: 'cw-pppoe-fields', class: 'cw-form-grid cw-block-space' }, [
					field('cw-pppoe-user', '宽带账号', 'text', this.state.username, '例如运营商提供的手机号或宽带识别账号。', { autocomplete: 'username' }),
					field('cw-pppoe-pass', '宽带密码', 'password', this.state.wanPassword, '留空会保留已有密码；新装 PPPoE 必须填写。', { autocomplete: 'new-password' })
				])
			];
		}
		else if (this.step === 1) {
			title = '设置 Wi‑Fi'; description = '三组无线使用同一名称和密码，5 GHz 保持设备默认的安全带宽，HE160 不在向导中启用。';
			content = [
				E('label', { class: 'cw-choice' }, [
					E('input', { id: 'cw-wifi-enable', type: 'checkbox', checked: this.state.enableWifi ? '' : null }),
					E('span', {}, [ E('strong', {}, '完成后启用无线网络'), E('small', {}, '首轮验收仍建议保留有线管理连接。') ])
				]),
				E('div', { id: 'cw-wifi-fields', class: 'cw-form-grid cw-block-space' }, [
					field('cw-wifi-ssid', 'Wi‑Fi 名称', 'text', this.state.ssid, '2.4 GHz 与 5 GHz 使用相同名称。', { maxlength: '32' }),
					field('cw-wifi-pass', 'Wi‑Fi 密码', 'password', this.state.wifiPassword, '至少 8 个字符，使用 WPA2/WPA3 混合模式。', { autocomplete: 'new-password' })
				])
			];
		}
		else {
			title = '保护管理后台'; description = '设置一个不同于宽带和 Wi‑Fi 的管理员密码。';
			content = [
				E('div', { class: 'cw-form-grid' }, [
					field('cw-admin-pass', '新管理员密码', 'password', this.state.adminPassword, '至少 10 个字符，建议使用密码管理器生成。', { autocomplete: 'new-password' }),
					field('cw-admin-confirm', '再次输入', 'password', this.state.adminConfirm, '密码只提交给当前路由器，不写入 Git。', { autocomplete: 'new-password' })
				]),
				E('div', { class: 'cw-panel cw-summary' }, [
					E('strong', {}, '即将应用'),
					E('ul', { class: 'cw-status-list' }, [
						E('li', {}, [ E('span', {}, '主 WAN'), E('strong', {}, this.state.mode === 'pppoe' ? 'PPPoE 拨号' : 'DHCP 自动获取') ]),
						E('li', {}, [ E('span', {}, 'Wi‑Fi'), E('strong', {}, this.state.enableWifi ? this.state.ssid : '保持关闭') ]),
						E('li', {}, [ E('span', {}, 'OpenClash'), E('strong', {}, '不安装') ])
					])
				])
			];
		}

		var bodyNodes = [
			E('div', { class: 'cw-error', role: 'alert' }),
			E('h2', {}, title), E('p', { class: 'cw-step-description' }, description)
		].concat(content, [
			E('div', { class: 'cw-wizard-nav' }, [
				E('button', { class: 'cbi-button-reset', click: this.back.bind(this) }, this.step === 0 ? '暂时离开' : '上一步'),
				E('button', { class: 'cbi-button-apply', click: this.next.bind(this) }, this.step === 2 ? '保存并应用' : '继续')
			])
		]);
		dom.content(this.body, bodyNodes);

		if (this.step === 0) {
			var modeInputs = this.body.querySelectorAll('input[name="cw-wan-mode"]');
			var syncWanFields = function() {
				var selected = self.body.querySelector('input[name="cw-wan-mode"]:checked');
				var fields = document.getElementById('cw-pppoe-fields');
				if (fields) fields.hidden = !selected || selected.value !== 'pppoe';
			};
			modeInputs.forEach(function(input) { input.addEventListener('change', syncWanFields); });
			syncWanFields();
		}
		if (this.step === 1) {
			var wifiToggle = document.getElementById('cw-wifi-enable');
			var syncWifiFields = function() {
				var fields = document.getElementById('cw-wifi-fields');
				if (fields) fields.hidden = !wifiToggle || !wifiToggle.checked;
			};
			if (wifiToggle) wifiToggle.addEventListener('change', syncWifiFields);
			syncWifiFields();
		}
	},

	applySettings: function() {
		var self = this;
		ui.showModal('正在应用设置', [ E('p', { class: 'spinning' }, '请保持有线连接，不要关闭路由器。') ]);

		uci.set('network', 'wan', 'device', 'wan');
		uci.set('network', 'wan', 'proto', this.state.mode);
		if (this.state.mode === 'pppoe') {
			uci.set('network', 'wan', 'username', this.state.username);
			if (this.state.wanPassword) uci.set('network', 'wan', 'password', this.state.wanPassword);
			uci.set('network', 'wan', 'ipv6', 'auto');
		}
		else {
			uci.unset('network', 'wan', 'username');
			uci.unset('network', 'wan', 'password');
			uci.unset('network', 'wan', 'ipv6');
		}

		var wifiPassword = this.state.wifiPassword || this.existingWifiPassword();
		uci.sections('wireless', 'wifi-device', function(section) { uci.set('wireless', section['.name'], 'country', 'CN'); });
		uci.sections('wireless', 'wifi-iface', function(section) {
			if (section.mode !== 'ap') return;
			uci.set('wireless', section['.name'], 'network', 'lan');
			uci.set('wireless', section['.name'], 'ssid', self.state.ssid);
			uci.set('wireless', section['.name'], 'encryption', 'sae-mixed');
			if (wifiPassword) uci.set('wireless', section['.name'], 'key', wifiPassword);
			uci.set('wireless', section['.name'], 'disabled', self.state.enableWifi ? '0' : '1');
		});
		uci.set('company', 'main', 'setup_complete', '1');
		uci.set('company', 'main', 'setup_version', '1');

		Promise.resolve(callSetPassword('root', this.state.adminPassword))
			.then(function(result) { if (result !== true && result !== 0) throw new Error('管理员密码设置失败'); })
			.then(function() { return uci.save(); })
			.then(function() { return uci.apply(); })
			.then(function() {
				ui.showModal('基础设置已保存', [
					E('p', {}, '路由器正在重新加载网络。保持有线连接，稍后打开控制中心。'),
					E('div', { class: 'right' }, E('a', { class: 'btn', href: L.url('admin', 'company') }, '进入控制中心'))
				]);
				window.setTimeout(function() { window.location.href = L.url('admin', 'company'); }, 5000);
			})
			.catch(function(error) {
				ui.hideModal();
				self.showError('保存失败：' + (error.message || error));
			});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
