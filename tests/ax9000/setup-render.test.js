'use strict';

const fs = require('fs');

const setupPath = process.argv[2];
if (!setupPath)
	throw new Error('setup view path is required');

class TestNode {
	constructor() {
		this.parentNode = null;
	}
}

class TestText extends TestNode {
	constructor(value) {
		super();
		this.value = String(value);
	}
	toString() { return this.value; }
}

class TestElement extends TestNode {
	constructor(tag) {
		super();
		this.tagName = String(tag).toUpperCase();
		this.attributes = {};
		this.children = [];
		this.hidden = false;
		this.checked = false;
		this.value = '';
		this.classList = { add: function() {} };
		this[Symbol.toStringTag] = 'HTML' + String(tag).replace(/(^|-)([a-z])/g, function(_, dash, letter) {
			return letter.toUpperCase();
		}) + 'Element';
	}
	get firstChild() { return this.children[0] || null; }
	get lastChild() { return this.children[this.children.length - 1] || null; }
	appendChild(child) {
		child.parentNode = this;
		this.children.push(child);
		return child;
	}
	removeChild(child) {
		const index = this.children.indexOf(child);
		if (index >= 0) this.children.splice(index, 1);
		return child;
	}
	setAttribute(key, value) {
		this.attributes[key] = value;
		if (key === 'id') this.id = value;
		if (key === 'value') this.value = value;
		if (key === 'checked' && value !== null) this.checked = true;
	}
	addEventListener() {}
	scrollIntoView() {}
	querySelectorAll(selector) { return findAll(this, selector); }
	querySelector(selector) { return findAll(this, selector)[0] || null; }
}

function descendants(node) {
	const output = [];
	if (!(node instanceof TestElement)) return output;
	for (const child of node.children) {
		if (child instanceof TestElement) {
			output.push(child);
			output.push.apply(output, descendants(child));
		}
	}
	return output;
}

function matches(node, selector) {
	if (selector === '[data-idref]') return false;
	if (selector[0] === '#') return node.attributes.id === selector.slice(1);
	if (selector[0] === '.') return String(node.attributes.class || '').split(/\s+/).includes(selector.slice(1));
	const inputName = selector.match(/^input\[name="([^"]+)"\](?::checked)?$/);
	if (inputName)
		return node.tagName === 'INPUT' && node.attributes.name === inputName[1] && (!selector.endsWith(':checked') || node.checked);
	return node.tagName === selector.toUpperCase();
}

function findAll(root, selector) {
	return descendants(root).filter(function(node) { return matches(node, selector); });
}

function collectText(node) {
	if (node instanceof TestText) return node.value;
	if (!(node instanceof TestElement)) return '';
	return node.children.map(collectText).join('');
}

const dom = {
	elem: function(node) { return node instanceof TestNode; },
	append: function(node, children) {
		if (!(node instanceof TestElement)) return null;
		if (Array.isArray(children)) {
			for (let i = 0; i < children.length; i++) {
				if (this.elem(children[i]))
					node.appendChild(children[i]);
				else if (children[i] !== null && children[i] !== undefined)
					node.appendChild(document.createTextNode(String(children[i])));
			}
			return node.lastChild;
		}
		if (this.elem(children)) return node.appendChild(children);
		if (children !== null && children !== undefined)
			node.appendChild(document.createTextNode(String(children)));
		return node.lastChild;
	},
	content: function(node, children) {
		while (node.firstChild) node.removeChild(node.firstChild);
		return this.append(node, children);
	}
};

let renderedRoot = null;
const document = {
	createTextNode: function(value) { return new TestText(value); },
	getElementById: function(id) { return renderedRoot ? findAll(renderedRoot, '#' + id)[0] || null : null; }
};

function E(tag, attributes, children) {
	const element = new TestElement(tag);
	for (const key of Object.keys(attributes || {})) {
		const value = attributes[key];
		if (value !== null && typeof value !== 'function') element.setAttribute(key, value);
	}
	dom.append(element, children);
	return element;
}

const view = { extend: function(specification) { return specification; } };
const rpc = { declare: function() { return function() { return Promise.resolve(true); }; } };
const uci = {
	load: function() { return Promise.resolve(); },
	get: function() { return null; },
	sections: function() {},
	set: function() {},
	unset: function() {},
	save: function() { return Promise.resolve(); },
	apply: function() { return Promise.resolve(); }
};
const ui = { showModal: function() {}, hideModal: function() {} };
const L = { url: function() { return '/'; } };
const window = { scrollTo: function() {}, location: { href: '' }, setTimeout: function() {} };

const source = fs.readFileSync(setupPath, 'utf8');
const factory = new Function('view', 'dom', 'ui', 'rpc', 'uci', 'E', 'L', 'document', 'window', source);
const specification = factory(view, dom, ui, rpc, uci, E, L, document, window);
const instance = Object.create(specification);
renderedRoot = instance.render();

const text = collectText(renderedRoot);
if (/\[object HTML[A-Za-z]+Element\]/.test(text))
	throw new Error('setup view rendered DOM nodes as text: ' + text.match(/\[object HTML[A-Za-z]+Element\](?:,\[object HTML[A-Za-z]+Element\])*/)[0]);

const choices = findAll(renderedRoot, 'input[name="cw-wan-mode"]');
const choiceValues = choices.map(function(node) { return node.value; }).sort().join(',');
if (choiceValues !== 'dhcp,pppoe')
	throw new Error('first setup screen must directly render DHCP and PPPoE choices');
if (!text.includes('设置主宽带'))
	throw new Error('first setup screen must clearly name the main-WAN task');
if (document.getElementById('cw-wired-confirm'))
	throw new Error('wired confirmation must be advisory, not a blocking checkbox');

console.log('setup DOM render and directly accessible WAN choices: ok');
