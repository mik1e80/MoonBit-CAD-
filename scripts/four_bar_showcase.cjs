'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
let write = false, target = 'js';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--write') write = true;
  else if (args[i] === '--check') {
    if (args.includes('--write')) throw new Error('Choose --write or --check');
  } else if (args[i] === '--target') {
    target = args[++i];
    assert.ok(['js', 'wasm', 'wasm-gc'].includes(target), 'Use js, wasm or wasm-gc');
  } else throw new Error('Usage: node scripts/four_bar_showcase.cjs [--check | --write] [--target js|wasm|wasm-gc]');
}
const executable = process.platform === 'win32' ? 'moon.exe' : 'moon';
const moon = process.env.MOON_HOME
  ? path.join(process.env.MOON_HOME, 'bin', executable) : executable;
const result = spawnSync(moon, ['run', 'examples/four_bar', '--target', target], {
  cwd: root, encoding: 'utf8', timeout: 120_000, maxBuffer: 4 * 1024 * 1024,
});
if (result.error || result.status !== 0)
  throw new Error(`Four-bar solve failed: ${result.error?.message || ''}\n${result.stdout || ''}\n${result.stderr || ''}`);
const records = result.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
const [metadata, ...poses] = records;
assert.deepEqual(metadata, {
  kind: 'mechanism', lengths: { AD: 80, AB: 30, BC: 70, CD: 50 },
  upper_assembly: true, free_local_dof: 1, pose_count: 25,
});
assert.equal(poses.length, 25);
const near = (actual, expected, label) =>
  assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) <= 5e-6,
    `${label}: ${actual}; expected ${expected}`);
const distance = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);
for (const [index, pose] of poses.entries()) {
  const degrees = index <= 12 ? index * 15 : 180 - (index - 12) * 15;
  assert.equal(pose.kind, 'pose');
  assert.equal(pose.index, index);
  assert.equal(pose.degrees, degrees);
  assert.equal(pose.direction, index <= 12 ? 'forward' : 'reverse');
  assert.deepEqual(pose.constraint_ids, poses[0].constraint_ids, 'Constraint handles changed');
  const angle = degrees * Math.PI / 180;
  const b = [30 * Math.cos(angle), 30 * Math.sin(angle)];
  // Independent circle-circle intersection; used for checking, never drawing.
  const delta = [80 - b[0], -b[1]];
  const span = Math.hypot(...delta);
  const along = (70 ** 2 - 50 ** 2 + span ** 2) / (2 * span);
  const offset = Math.sqrt(70 ** 2 - along ** 2);
  const c = [
    b[0] + along * delta[0] / span - offset * delta[1] / span,
    b[1] + along * delta[1] / span + offset * delta[0] / span,
  ];
  const expected = [[0, 0], b, c, [80, 0]];
  assert.equal(pose.points.length, 4);
  pose.points.forEach((point, joint) => {
    assert.equal(point.length, 2);
    point.forEach((value, axis) => near(value, expected[joint][axis],
      `${index}.${['A', 'B', 'C', 'D'][joint]}[${axis}]`));
  });
  const [a0, b0, c0, d0] = pose.points;
  near(distance(a0, b0), 30, 'AB');
  near(distance(b0, c0), 70, 'BC');
  near(distance(c0, d0), 50, 'CD');
  near(distance(a0, d0), 80, 'AD');
  assert.ok((d0[0] - b0[0]) * (c0[1] - b0[1]) -
    (d0[1] - b0[1]) * (c0[0] - b0[0]) > 0, 'Assembly branch changed');
  const report = pose.report;
  assert.equal(report.status, 'Satisfied');
  assert.equal(report.local_dof, 0);
  assert.equal(report.variables, 8);
  assert.equal(report.equations, 8);
  assert.equal(report.residuals.length, 6);
  assert.equal(new Set(report.residuals.map(row => row.id)).size, 6);
  assert.ok(report.max_tolerance_ratio <= 1);
  for (const row of report.residuals) {
    assert.equal(row.active, true);
    for (const key of ['length_error', 'angular_error', 'tolerance_ratio'])
      assert.ok(Number.isFinite(row[key]) && row[key] >= 0);
    assert.ok(row.tolerance_ratio <= 1);
  }
  near(report.max_tolerance_ratio,
    Math.max(...report.residuals.map(row => row.tolerance_ratio)), 'Maximum tolerance ratio');
  if (index > 12) {
    const forward = poses[degrees / 15];
    pose.points.forEach((point, joint) =>
      point.forEach((value, axis) => near(value, forward.points[joint][axis], 'Forward/reverse pose')));
  }
}
const forward = poses.slice(0, 13);
const n = value => String(Number(value.toFixed(3)));
const escape = value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const text = (x, y, value, cls = '', extra = '') =>
  `<text x="${n(x)}" y="${n(y)}" class="${cls}" ${extra}>${escape(value)}</text>`;
const line = (a, b, color, width = 3, extra = '') =>
  `<line x1="${n(a[0])}" y1="${n(a[1])}" x2="${n(b[0])}" y2="${n(b[1])}" stroke="${color}" stroke-width="${width}" stroke-linecap="round" ${extra}/>`;
const orange = '#c27624', blue = '#245eb8', green = '#258475';
const transform = (point, x, y, scale) => [x + point[0] * scale, y - point[1] * scale];
function links(pose, x, y, scale, opacity = 1, labels = false) {
  const points = pose.points.map(point => transform(point, x, y, scale));
  const [a, b, c, d] = points;
  let out = `<g opacity="${opacity}">`;
  out += line(a, d, '#8c9ab0', 2, 'stroke-dasharray="6 5"');
  out += line(a, b, orange, labels ? 5 : 3);
  out += line(b, c, blue, labels ? 5 : 3);
  out += line(c, d, green, labels ? 5 : 3);
  points.forEach((point, index) => {
    out += `<circle cx="${n(point[0])}" cy="${n(point[1])}" r="${labels ? 5.5 : 3.5}" fill="#fff" stroke="${['#4b5f7b', orange, blue, '#4b5f7b'][index]}" stroke-width="2"/>`;
  });
  if (labels) {
    [a, d].forEach(point => {
      out += `<path d="M ${n(point[0])} ${n(point[1] + 7)} l -11 15 h 22 Z" fill="#d6dfeb" stroke="#8c9ab0"/>`;
      out += line([point[0] - 17, point[1] + 24], [point[0] + 17, point[1] + 24], '#8c9ab0', 1.5);
    });
    out += text(a[0], a[1] + 44, 'A / fixed', 'joint', 'text-anchor="middle"');
    out += text(d[0], d[1] + 44, 'D / fixed', 'joint', 'text-anchor="middle"');
    out += text(b[0] - 14, b[1] - 12, 'B', 'joint');
    out += text(c[0] + 12, c[1] - 10, 'C', 'joint');
    [[a, b, 'AB 30'], [b, c, 'BC 70'], [c, d, 'CD 50']].forEach(([p, q, name]) => {
      out += text((p[0] + q[0]) / 2 + (name === 'AB 30' ? -26 : 0),
        (p[1] + q[1]) / 2 - 12, name, 'link-label', 'text-anchor="middle"');
    });
  }
  return out + '</g>';
}
const project = point => transform(point, 255, 509, 4.1);
const trail = (joint, color) => {
  const points = forward.map(pose => project(pose.points[joint]));
  return `<polyline points="${points.map(point => point.map(n).join(',')).join(' ')}" fill="none" stroke="${color}" stroke-width="1.6" stroke-dasharray="3 5" opacity=".65"/>` +
    points.map(point => `<circle cx="${n(point[0])}" cy="${n(point[1])}" r="2.5" fill="${color}" opacity=".7"/>`).join('');
};
let mini = '';
for (const [row, index] of [0, 6, 12].entries()) {
  const y = 330 + row * 112;
  mini += text(820, y - 36, `${forward[index].degrees}°`, 'angle');
  mini += links(forward[index], 938, y, 1.55);
  mini += text(938, y + 24, 'A', 'mini-joint', 'text-anchor="middle"');
  mini += text(1062, y + 24, 'D', 'mini-joint', 'text-anchor="middle"');
  if (row < 2) mini += `<line x1="820" y1="${y + 36}" x2="1212" y2="${y + 36}" stroke="#e5eaf2"/>`;
}
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="800" viewBox="0 0 1280 800" role="img" aria-labelledby="title desc">
<title id="title">Four-bar linkage: continuous forward and reverse angle sweep</title>
<desc id="desc">Fixed supports A and D are 80 mm apart. AB is 30, BC 70, and CD 50 mm. Twenty-five sequential solutions drive the crank from 0 to 180 degrees in 15 degree steps and back to 0. The plot shows returned joint trajectories and poses at 0, 90 and 180 degrees.</desc>
<style>
text{font-family:Segoe UI,Arial,sans-serif;fill:#1c2b42}
.eyebrow{font-size:12px;letter-spacing:2px;font-weight:700;fill:#245eb8}
.title{font-size:34px;font-weight:700;letter-spacing:-.7px}
.subtitle{font-size:16px;fill:#5c6d84}
.panel-title{font-size:20px;font-weight:700}
.note{font-size:13px;fill:#60738d}
.joint{font-size:14px;font-weight:600}
.link-label{font-size:13px;font-weight:600;paint-order:stroke;stroke:#fff;stroke-width:5px;stroke-linejoin:round}
.mini-joint{font-size:12px;fill:#60738d}
.angle{font-size:24px;font-weight:600}
.metric{font-size:19px;font-weight:700}
.detail{font-size:14px;fill:#536b89}
</style>
<rect width="1280" height="800" fill="#f5f7fb"/>
${text(40, 44, 'MOONBIT CAD SKETCH / MECHANISM 01', 'eyebrow')}
${text(40, 97, 'Four-bar linkage in motion', 'title')}
${text(40, 133, 'AB 30 · BC 70 · CD 50 · fixed ground AD 80 mm / actual solver output, same sketch throughout', 'subtitle')}
<rect x="40" y="174" width="730" height="440" rx="18" fill="#fff" stroke="#dce3ed"/>
${text(68, 211, 'Joint trajectories and assembly branch', 'panel-title')}
${text(68, 240, '13 forward poses · dots trace B and C · bold links show 90°', 'note')}
${trail(1, orange)}
${trail(2, blue)}
${links(forward[0], 255, 509, 4.1, .18)}
${links(forward[12], 255, 509, 4.1, .18)}
${links(forward[6], 255, 509, 4.1, 1, true)}
${line([70, 584], [94, 584], orange, 4)}
${text(102, 589, 'Crank AB', 'note')}
${line([252, 584], [276, 584], blue, 4)}
${text(284, 589, 'Coupler BC', 'note')}
${line([454, 584], [478, 584], green, 4)}
${text(486, 589, 'Rocker CD', 'note')}
<rect x="794" y="174" width="446" height="440" rx="18" fill="#fff" stroke="#dce3ed"/>
${text(822, 211, 'Selected solved positions', 'panel-title')}
${mini}
<rect x="40" y="640" width="1200" height="124" rx="18" fill="#e9eff9" stroke="#d4dfef"/>
${text(66, 676, '25 satisfied poses', 'metric')}
${text(425, 676, '1 free DOF → 0 driven DOF', 'metric')}
${text(880, 676, '0° → 180° → 0°', 'metric')}
${text(66, 711, 'One angle constraint is edited; B and C are solved from the previous pose. No per-frame coordinate assignments.', 'detail')}
${text(66, 740, 'Forward/reverse coordinates agree within 5e-6 mm. Link lengths and the chosen assembly branch are preserved.', 'detail')}
</svg>
`;
const imagePath = path.join(root, 'docs', 'images', 'four-bar-motion.svg');
if (write) {
  fs.mkdirSync(path.dirname(imagePath), { recursive: true });
  fs.writeFileSync(imagePath, svg);
} else assert.equal(fs.readFileSync(imagePath, 'utf8'), svg,
  'Committed SVG is stale. Run --write and review the result.');
const output = path.join(root, '_build', 'showcase');
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, `four-bar-${target}.json`), JSON.stringify({ target, metadata, poses }, null, 2) + '\n');
const csv = 'index,direction,angle_degrees,Ax,Ay,Bx,By,Cx,Cy,Dx,Dy,status,local_dof\n' +
  poses.map(pose => [pose.index, pose.direction, pose.degrees, ...pose.points.flat(),
    pose.report.status, pose.report.local_dof].join(',')).join('\n') + '\n';
fs.writeFileSync(path.join(output, `four-bar-${target}.csv`), csv);
console.log(`Verified ${poses.length} forward/reverse poses on ${target}; lengths, assembly branch, 1→0 DOF and analytic coordinates checked.`);
console.log(`${write ? 'Generated' : 'Checked'} docs/images/four-bar-motion.svg; raw JSON and CSV: _build/showcase/four-bar-${target}.*`);
