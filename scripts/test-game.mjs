// Compile runtime Lua and run mock-based regressions in isolated game LuaJIT
// environments. This does not start a shift, move a vehicle or change settings.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const endpoint = process.env.BEAMNG_MCP_URL || 'http://127.0.0.1:29292/mcp';
let id = 0;
async function rpc(method, params) {
  const response = await fetch(endpoint, {method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({jsonrpc: '2.0', id: ++id, method, params}), signal: AbortSignal.timeout(30000)});
  if (!response.ok) throw new Error(`Game MCP HTTP ${response.status}`);
  const result = await response.json();
  if (result.error) throw new Error(result.error.message);
  return result.result;
}
async function lua(code) {
  const result = await rpc('tools/call', {name: 'run_lua', arguments: {code}});
  if (result.isError) throw new Error(result.content[0].text);
  return JSON.parse(result.content[0].text);
}
await rpc('initialize', {protocolVersion: '2025-11-25', capabilities: {},
  clientInfo: {name: 'TaxiDriver regressions', version: '5.0.2'}});
const sources = {};
async function collect(relative) {
  for (const entry of await fs.readdir(path.join(root, relative), {withFileTypes: true})) {
    const name = `${relative}/${entry.name}`;
    if (entry.isDirectory()) await collect(name);
    else if (name.endsWith('.lua')) sources[name] = (await fs.readFile(path.join(root, name), 'utf8')).replace(/\r\n/g, '\n');
  }
}
await collect('lua');
await collect('tests/lua');
sources['ui/modules/apps/TaxiDriverHUD/hud-model.js'] = await fs.readFile(path.join(root, 'ui/modules/apps/TaxiDriverHUD/hud-model.js'), 'utf8');
const tests = Object.keys(sources).filter(name => name.startsWith('tests/lua/'));
const runtime = Object.fromEntries(Object.entries(sources).filter(([name]) => name.startsWith('lua/')));
const compilation = await lua(`local sources=jsonDecode(${JSON.stringify(JSON.stringify(runtime))});local errors={};local count=0;for p,s in pairs(sources) do local f,e=loadstring(s,'@'..p);count=count+1;if not f then errors[#errors+1]={path=p,message=e} end end;return jsonEncode({count=count,errors=errors})`);
if (Object.keys(compilation.errors).length) throw new Error(JSON.stringify(compilation.errors));
const runner = await fs.readFile(path.join(root, 'scripts/run-lua-regressions.lua'), 'utf8');
const regressions = await lua(`local run=assert(loadstring(${JSON.stringify(runner)},'@scripts/run-lua-regressions.lua'))();return jsonEncode(run(${JSON.stringify(root.replace(/\\/g, '/'))},jsonDecode(${JSON.stringify(JSON.stringify(tests))}),jsonDecode(${JSON.stringify(JSON.stringify(sources))})))`);
const report = {compilation, regressions};
await fs.mkdir(path.join(root, 'tests/ui/artifacts'), {recursive: true});
await fs.writeFile(path.join(root, 'tests/ui/artifacts/lua-game-report.json'), JSON.stringify(report, null, 2));
if (Object.keys(regressions.failed).length) throw new Error(JSON.stringify(regressions.failed));
console.log(`Game LuaJIT: ${compilation.count} runtime files compiled; ${regressions.passed.length} regression files passed.`);
