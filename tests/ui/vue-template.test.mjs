import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { test } from 'node:test';
import { parse, compile, NodeTypes } from '@vue/compiler-dom';

const templatePath = new URL('../../ui/modules/apps/TaxiDriverHUD/hud-template.html', import.meta.url);
const source = await fs.readFile(templatePath, 'utf8');
const ast = parse(source);
const elements = [];
function visit(node) {
  if (node.type === NodeTypes.ELEMENT) elements.push(node);
  for (const child of node.children || []) visit(child);
}
visit(ast);
function directive(node, name) {
  return node.props.find(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === name);
}
function attribute(node, name) {
  return node.props.find(prop => prop.type === NodeTypes.ATTRIBUTE && prop.name === name)?.value?.content;
}

test('the complete HUD compiles as Vue without legacy directives or filters', () => {
  const errors = [];
  const result = compile(source, { mode: 'module', prefixIdentifiers: true, onError: error => errors.push(error) });
  assert.deepEqual(errors, []);
  assert.match(result.code, /export function render/);
  assert.doesNotMatch(source, /\bng-[\w-]+\s*=/);
  assert.doesNotMatch(source, /\|\s*(?:number|limitTo)\b|\$index/);
  assert.doesNotMatch(source, /<style\b|<script\b|\bon\w+\s*=/);
  for (const screen of ['taxi-shell', 'taxi-compact', 'taxi-settings', 'taxi-profile',
    'taxi-fleet', 'taxi-order-card', 'taxi-trip-dashboard', 'taxi-fuel', 'taxi-next-offer']) {
    assert(elements.some(node => (attribute(node, 'class') || '').split(/\s+/).includes(screen)), `${screen} must remain present`);
  }
});

test('all repeated rows have stable keys and scoped conditions', () => {
  const repeated = elements.filter(node => directive(node, 'for'));
  assert(repeated.length >= 25, 'all lists must survive the migration');
  for (const node of repeated) {
    assert(node.props.some(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === 'bind' && prop.arg?.content === 'key'), node.loc.source);
    assert(!directive(node, 'if'), 'repeat conditions must be inside the keyed template');
  }
});

test('numeric ranges, boolean switches and string fields retain their model types', () => {
  const modelInputs = elements.filter(node => node.tag === 'input' && directive(node, 'model'));
  assert(modelInputs.length >= 45, 'all editable controls must survive the migration');
  for (const node of modelInputs) {
    const model = directive(node, 'model');
    const numeric = model.modifiers.some(modifier => modifier.content === 'number');
    const type = attribute(node, 'type');
    assert.equal(numeric, type === 'range' || type === 'number', model.exp.content);
    if (type === 'range' || type === 'text') {
      const change = node.props.find(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === 'on' && prop.arg?.content === 'input');
      if (model.exp.content !== 'cheatRating') assert(change, `live input handler missing: ${model.exp.content}`);
    }
    if (type === 'checkbox') assert(node.props.some(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === 'on' && prop.arg?.content === 'change'));
  }
  const customRange = modelInputs.find(node => directive(node, 'model').exp.content === 'settings.customDifficulty[control.key]');
  for (const bound of ['min', 'max', 'step']) assert(customRange.props.some(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === 'bind' && prop.arg?.content === bound));
  const fuelRange = modelInputs.find(node => directive(node, 'model').exp.content === 'refuel.amount');
  assert(fuelRange.props.some(prop => prop.type === NodeTypes.DIRECTIVE && prop.name === 'bind' && prop.arg?.content === 'max'));
});
