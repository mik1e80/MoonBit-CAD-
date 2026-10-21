'use strict';

// Closed-form coordinates are verification oracles only. Draw returned geometry.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
let write = false;
let target = 'js';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--write') write = true;
  else if (args[i] === '--check') {
    if (args.includes('--write')) throw new Error('Choose --write or --check');
  } else if (args[i] === '--target') {
    target = args[++i];
    assert.ok(['js', 'wasm', 'wasm-gc'].includes(target), 'Use js, wasm or wasm-gc');
  } else throw new Error('Usage: node scripts/bracket_showcase.cjs [--check | --write] [--target js|wasm|wasm-gc]');
}
const executable = process.platform === 'win32' ? 'moon.exe' : 'moon';
const moon = process.env.MOON_HOME
  ? path.join(process.env.MOON_HOME, 'bin', executable)
  : executable;
const run = spawnSync(moon, ['run', 'cmd/bracket_demo', '--target', target], {
  cwd: root, encoding: 'utf8', timeout: 120_000, maxBuffer: 4 * 1024 * 1024,
});
if (run.error || run.status !== 0) {
  throw new Error(`MoonBit showcase failed: ${run.error?.message || ''}\n${run.stdout || ''}\n${run.stderr || ''}`);
}
const events = run.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
assert.deepEqual(events.map(event => event.stage),
  ['initial', 'widened', 'larger_holes', 'edited', 'conflict', 'recovered']);
const configurations = [
  [120, 80, 5, 20, 15], [160, 80, 5, 20, 15], [160, 80, 8, 20, 15],
  [160, 80, 8, 30, 15], [160, 80, 8, 30, 15], [160, 80, 8, 30, 15],
];
const near = (actual, expected, label) => {
  assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) <= 5e-6,
    `${label}: ${actual}, expected ${expected}`);
};
for (const [i, event] of events.entries()) {
  const [w, h, r, mx, my] = configurations[i];
  assert.deepEqual(event.parameters,
    { width: w, height: h, hole_radius: r, horizontal_margin: mx, vertical_margin: my });
  assert.deepEqual(event.constraint_ids, events[0].constraint_ids, 'Relation handles changed');
  assert.deepEqual(Object.keys(event.geometry).sort(), ['axis_points', 'corners', 'holes']);
  const expected = {
    corners: [[0, 0], [w, 0], [w, h], [0, h]],
    axis_points: [[w / 2, 0], [w / 2, h], [0, h / 2], [w, h / 2]],
    holes: [[mx, my, r], [w - mx, my, r], [mx, h - my, r], [w - mx, h - my, r]],
  };
  for (const field of Object.keys(expected)) {
    assert.equal(event.geometry[field].length, expected[field].length);
    event.geometry[field].forEach((row, rowIndex) => {
      assert.equal(row.length, expected[field][rowIndex].length);
      row.forEach((value, column) => near(value, expected[field][rowIndex][column],
        `${event.stage}.${field}[${rowIndex}][${column}]`));
    });
  }
  const report = event.report;
  assert.equal(report.variables, 28);
  assert.equal(report.local_dof, 0);
  assert.equal(report.residuals.length, 21);
  assert.equal(new Set(report.residuals.map(item => item.id)).size, 21);
  assert.equal(report.residuals.filter(item => item.active).length, i === 4 ? 21 : 20);
  for (const item of report.residuals) {
    for (const field of ['length_error', 'angular_error', 'tolerance_ratio']) {
      assert.ok(Number.isFinite(item[field]) && item[field] >= 0);
      if (!item.active) assert.equal(item[field], 0);
    }
  }
  near(report.max_tolerance_ratio,
    Math.max(...report.residuals.map(item => item.tolerance_ratio)), 'report maximum');
  if (i === 4) {
    assert.equal(event.applied, false);
    assert.ok(['Stalled', 'IterationLimit'].includes(report.status));
    assert.equal(report.equations, 29);
    assert.ok(report.residuals.some(item => item.active && item.tolerance_ratio > 1));
    assert.ok(report.residuals.find(item => item.id === event.constraint_ids.conflict).active);
    assert.deepEqual(event.geometry, events[3].geometry,
      'A failed attempt changed one of the 28 stored geometry values');
  } else {
    assert.equal(event.applied, true);
    assert.equal(report.status, 'Satisfied');
    assert.equal(report.equations, 28);
    assert.ok(report.max_tolerance_ratio <= 1);
    assert.ok(!report.residuals.find(item => item.id === event.constraint_ids.conflict).active);
  }
}

const n = value => String(Number(value.toFixed(3)));
const escape = value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const text = (x, y, value, cls = '', extra = '') =>
  `<text x="${n(x)}" y="${n(y)}" class="${cls}" ${extra}>${escape(value)}</text>`;
const line = (x1, y1, x2, y2, cls = '', extra = '') =>
  `<line x1="${n(x1)}" y1="${n(y1)}" x2="${n(x2)}" y2="${n(y2)}" class="${cls}" ${extra}/>`;
function panel(event, x, title, accent) {
  const p = event.parameters;
  const scale = 2.7; // Identical physical scale in the two panels.
  const originX = x + 292 - p.width * scale / 2;
  const originY = 508;
  const px = value => originX + value * scale;
  const py = value => originY - value * scale;
  const corners = event.geometry.corners;
  const hole = event.geometry.holes[0];
  const left = corners[0][0], right = corners[1][0];
  const top = corners[3][1], bottom = corners[0][1];
  const axis = event.geometry.axis_points;
  const radius = event.geometry.holes[0][2];
  let out = `<g>
<rect x="${x}" y="174" width="584" height="454" rx="18" fill="#ffffff" stroke="#dce3ed"/>
${text(x + 28, 213, title, 'panel-title')}
<rect x="${x + 430}" y="190" width="126" height="31" rx="15" fill="#e7f6ee"/>
${text(x + 493, 211, 'Satisfied / DOF 0', 'success', 'text-anchor="middle"')}
${text(x + 28, 242, `${p.width} × ${p.height} mm · 4 × R${p.hole_radius}`, 'muted')}
<path d="M ${corners.map(point => `${n(px(point[0]))} ${n(py(point[1]))}`).join(' L ')} Z" fill="${accent ? '#e9f1ff' : '#f0f3f7'}" stroke="${accent ? '#235fc1' : '#50627a'}" stroke-width="2.5"/>
${line(px(axis[0][0]), py(axis[0][1]) + 12, px(axis[1][0]), py(axis[1][1]) - 12, 'axis')}
${line(px(axis[2][0]) - 12, py(axis[2][1]), px(axis[3][0]) + 12, py(axis[3][1]), 'axis')}`;
  event.geometry.holes.forEach((point, index) => {
    const cx = px(point[0]), cy = py(point[1]), cr = point[2] * scale;
    out += `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(cr)}" fill="#ffffff" stroke="${accent ? '#235fc1' : '#50627a'}" stroke-width="2.3"/>`;
    out += line(cx - 5, cy, cx + 5, cy, 'center') + line(cx, cy - 5, cx, cy + 5, 'center');
    out += text(cx, cy - cr - 8, ['A', 'B', 'C', 'D'][index], 'hole-label', 'text-anchor="middle"');
  });
  const dimensionY = py(top) - 25;
  out += line(px(left), py(top) - 6, px(left), dimensionY - 5, 'extension');
  out += line(px(right), py(top) - 6, px(right), dimensionY - 5, 'extension');
  out += line(px(left) + 2, dimensionY, px(right) - 2, dimensionY, 'dimension',
    'marker-start="url(#arrow)" marker-end="url(#arrow)"');
  out += text((px(left) + px(right)) / 2, dimensionY - 8, `${p.width} mm`, 'dimension-label', 'text-anchor="middle"');
  const heightX = px(left) - 24;
  out += line(heightX, py(top) + 2, heightX, py(bottom) - 2, 'dimension',
    'marker-start="url(#arrow)" marker-end="url(#arrow)"');
  out += text(heightX - 9, (py(top) + py(bottom)) / 2, `${p.height}`,
    'dimension-label', `text-anchor="middle" transform="rotate(-90 ${n(heightX - 9)} ${n((py(top) + py(bottom)) / 2)})"`);
  const marginY = py(bottom) + 29;
  out += line(px(left), py(bottom) + 6, px(left), marginY + 4, 'extension');
  out += line(px(hole[0]), py(hole[1]) + radius * scale + 4, px(hole[0]), marginY + 4, 'extension');
  out += line(px(left) + 2, marginY, px(hole[0]) - 2, marginY, 'dimension',
    'marker-start="url(#arrow)" marker-end="url(#arrow)"');
  out += text((px(left) + px(hole[0])) / 2, marginY + 20, `${p.horizontal_margin}`, 'dimension-label', 'text-anchor="middle"');
  const verticalX = px(hole[0]) + radius * scale + 19;
  out += line(verticalX, py(hole[1]) + 2, verticalX, py(bottom) - 2, 'dimension',
    'marker-start="url(#arrow)" marker-end="url(#arrow)"');
  out += text(verticalX + 9, (py(hole[1]) + py(bottom)) / 2 + 5, `${p.vertical_margin}`, 'dimension-label');
  out += text(x + 28, 604, `Center-to-edge margins: ${p.horizontal_margin} mm horizontal / ${p.vertical_margin} mm vertical`, 'panel-note');
  return out + '</g>';
}
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="820" viewBox="0 0 1280 820" role="img" aria-labelledby="title desc">
<title id="title">Parametric bracket: initial and edited solver results</title>
<desc id="desc">A 120 by 80 plate with four radius 5 holes and 20 by 15 center margins changes to a 160 by 80 plate with radius 8 holes and 30 by 15 center margins. Both geometries come from the same MoonBit sketch. A conflicting width is rejected and disabling it restores a satisfied result.</desc>
<defs><marker id="arrow" viewBox="0 0 8 8" refX="4" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 8 0 L 0 4 L 8 8" fill="none" stroke="#77859b" stroke-width="1.2"/></marker></defs>
<style>
text{font-family:Segoe UI,Arial,sans-serif;fill:#1c2b42}
.eyebrow{font-size:12px;letter-spacing:2px;font-weight:700;fill:#235fc1}
.title{font-size:34px;font-weight:700;letter-spacing:-.7px}
.muted{font-size:16px;fill:#5c6d84}
.panel-title{font-size:21px;font-weight:700}
.success{font-size:12px;font-weight:600;fill:#23724b}
.axis{stroke:#98b0cf;stroke-width:1;stroke-dasharray:7 5}
.center{stroke:#7b8ca5;stroke-width:1}
.hole-label{font-size:12px;font-weight:600;fill:#526780}
.extension{stroke:#b2bdcc;stroke-width:1}
.dimension{stroke:#77859b;stroke-width:1}
.dimension-label{font-size:14px;fill:#526780}
.panel-note{font-size:13px;fill:#5c6d84}
.change{font-size:17px;font-weight:600}
.recovery{font-size:14px;fill:#526780}
</style>
<rect width="1280" height="820" fill="#f5f7fb"/>
${text(40, 44, 'MOONBIT CAD SKETCH / SHOWCASE 01', 'eyebrow')}
${text(40, 97, 'Parametric mounting plate', 'title')}
${text(40, 133, 'Actual solved geometry · same sketch and constraint handles · identical drawing scale', 'muted')}
${panel(events[0], 40, '01 / Initial sketch', false)}
${panel(events[3], 656, '02 / After parameter edits', true)}
<rect x="40" y="652" width="1200" height="130" rx="18" fill="#e9eff9" stroke="#d4dfef"/>
${text(66, 689, 'Width 120 → 160', 'change')}
${text(380, 689, 'Hole radius 5 → 8', 'change')}
${text(752, 689, 'Horizontal margin 20 → 30', 'change')}
${text(66, 724, '20 active relations / 28 equations / 28 variables · all four hole positions follow the design relations', 'recovery')}
${text(66, 752, 'Conflicting widths 160 and 170: not applied; all 28 geometry values retained. Disable conflict: Satisfied.', 'recovery')}
</svg>
`;
const imagePath = path.join(root, 'docs', 'images', 'bracket-before-after.svg');
if (write) {
  fs.mkdirSync(path.dirname(imagePath), { recursive: true });
  fs.writeFileSync(imagePath, svg);
} else {
  assert.equal(fs.readFileSync(imagePath, 'utf8'), svg,
    'Committed SVG is stale. Rebuild with --write and review the result.');
}
const resultsPath = path.join(root, '_build', 'showcase', `bracket-${target}.json`);
fs.mkdirSync(path.dirname(resultsPath), { recursive: true });
fs.writeFileSync(resultsPath, JSON.stringify({ target, events }, null, 2) + '\n');
console.log(`Verified ${events.length} real solver stages on ${target}; four satisfied stages, conflict retention and recovery.`);
console.log(`${write ? 'Generated' : 'Checked'} ${path.relative(root, imagePath)}; raw diagnostics: ${path.relative(root, resultsPath)}`);
