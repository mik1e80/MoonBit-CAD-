'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { checkSnapshotSource } = require('./snapshot_provenance.cjs');
const root = path.resolve(__dirname, '..');
const groups = { analytic: 60, translation: 60, rotation: 60, scaling: 60, perturbation: 100, extreme: 60 };
const families = ['triangle', 'rectangle', 'mirror_circles', 'line_circle_tangent'];
const shape = { triangle: [3, 0, 6, 6, 4], rectangle: [4, 0, 8, 9, 7],
  mirror_circles: [4, 2, 10, 10, 6], line_circle_tangent: [3, 1, 7, 7, 5] };
let target = 'js', write = false, strictSnapshot = false, selection;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--write') write = true;
  else if (args[i] === '--require-current-snapshot') strictSnapshot = true;
  else if (args[i] === '--check') {
    assert.ok(!args.includes('--write'), 'Choose --check or --write');
  } else if (args[i] === '--target') target = args[++i];
  else if (args[i] === '--case') selection = args[++i];
  else throw new Error('Usage: node scripts/validation_suite.cjs [--check | --write] [--require-current-snapshot] [--target js|wasm|wasm-gc|native] [--case group:index]');
}
assert.ok(['js', 'wasm', 'wasm-gc', 'native'].includes(target), 'Unknown target');
assert.ok(!selection || !write, '--case cannot write a complete-suite snapshot');
assert.ok(!strictSnapshot || (!selection && !write), '--require-current-snapshot requires a full --check');
const executable = process.platform === 'win32' ? 'moon.exe' : 'moon';
const moon = process.env.MOON_HOME ? path.join(process.env.MOON_HOME, 'bin', executable) : executable;
const version = spawnSync(moon, ['version', '--all'], { cwd: root, encoding: 'utf8', timeout: 30_000 });
assert.equal(version.status, 0, version.stderr || version.error?.message);
const processResult = spawnSync(moon, ['run', 'cmd/validation', '--target', target], {
  cwd: root, encoding: 'utf8', timeout: 180_000, maxBuffer: 16 * 1024 * 1024,
});
// Preserve raw output even when compilation, execution, parsing or corpus
// verification fails before per-model results can be constructed.
const output = path.join(root, '_build', 'validation');
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, `${target}.jsonl`), processResult.stdout || '');
fs.writeFileSync(path.join(output, `${target}.stderr.log`),
  (processResult.stderr || '') + (processResult.error?.stack || ''));
assert.equal(processResult.status, 0, processResult.stderr || processResult.error?.message);
const [metadata, ...records] = processResult.stdout.trim().split(/\r?\n/).map(JSON.parse);
assert.deepEqual(metadata, { kind: 'validation_suite', schema: 1, seed: 20261022, cases: 400 });
assert.equal(records.length, 400, 'Missing or duplicated generated cases');

class ValidationFailure extends Error {
  constructor(category, message) { super(message); this.category = category; }
}
function demand(condition, category, message) {
  if (!condition) throw new ValidationFailure(category, message);
}
const finite = x => typeof x === 'number' && Number.isFinite(x);
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
const unit = a => { const length = Math.hypot(...a); return a.map(x => x / length); };
const maximum = a => Math.max(0, ...a);
function transformed(t, x, y) {
  return [t.x + (x * Math.cos(t.angle) - y * Math.sin(t.angle)) * t.scale,
    t.y + (x * Math.sin(t.angle) + y * Math.cos(t.angle)) * t.scale];
}
function prng(seed) {
  return () => {
    const value = 16807 * (seed % 127773) - 2836 * Math.floor(seed / 127773);
    seed = value > 0 ? value : value + 2147483647;
    return seed / 2147483647;
  };
}
// Separate JS generator checks the declared corpus, including every initial
// guess. It never supplies solved coordinates to MoonBit.
function expectedInput(row) {
  const draw = prng(20261022 + row.index * 37);
  for (let i = 0; i < 5; i++) draw();
  const parameters = [6 + 18 * draw(), 4 + 10 * draw(), 0.7 + 1.3 * draw(), 0.25 + 0.5 * draw()];
  const [w, h, r, f] = parameters;
  const t = { x: 0, y: 0, angle: 0, scale: 1 };
  if (row.group === 'translation') { t.x = (row.index - 30) * 5000; t.y = (row.index % 11 - 5) * 7000; }
  if (row.group === 'rotation') t.angle = -Math.PI + 2 * Math.PI * (row.index + 0.5) / 60;
  if (row.group === 'scaling') t.scale = Math.pow(10, -6 + 12 * row.index / 59);
  if (row.group === 'extreme')
    t.scale = [1e-150, 1e-100, 1e-50, 1e-12, 1e-9, 1e9, 1e12, 1e50, 1e80, 1e90][Math.floor(row.index / 4) % 10];
  const templates = [
    [[0, 0], [w, 0], [w * f, h]],
    [[0, 0], [w, 0], [w, h], [0, h]],
    [[-w, 0], [w, 0], [w * f, h], [w * f, -h]],
    [[-w, 0], [w, 0], [0, r]],
  ];
  const noise = (row.group === 'perturbation' ? 0.25 : 0.04) * r;
  const perturb = prng(row.seed + (row.group === 'perturbation' ? 100000 : 0));
  const points = templates[row.index % 4].map(p =>
    transformed(t, p[0] + noise * (2 * perturb() - 1), p[1] + noise * (2 * perturb() - 1)));
  const radii = Array.from({ length: shape[row.family][1] }, () => r * t.scale * (1 + 0.1 * perturb()));
  return { parameters, transform: t, points, radii };
}
function inspect(row) {
  const [pointCount, circleCount, variables, equations, relations] = shape[row.family];
  demand(row.status !== 'Error', 'solver_error', row.error);
  demand(row.status === 'Satisfied', 'not_converged', row.status);
  for (const [key, count] of [['points', pointCount], ['initial_points', pointCount], ['stored_points', pointCount]]) {
    demand(Array.isArray(row[key]) && row[key].length === count, 'invalid_output', key);
    demand(row[key].every(p => Array.isArray(p) && p.length === 2 && p.every(finite)),
      'non_finite_output', key);
  }
  for (const key of ['radii', 'initial_radii', 'stored_radii']) {
    demand(Array.isArray(row[key]) && row[key].length === circleCount, 'invalid_output', key);
    demand(row[key].every(r => finite(r) && r > 0), 'non_finite_output', key);
  }
  const t = row.transform, [w, h, r, f] = row.parameters;
  const scale = t.scale, lenTol = row.length_tolerance / scale;
  const angTol = row.angular_tolerance;
  demand(finite(scale) && scale > 0 && Math.abs(lenTol - 1e-7) < 1e-20 && angTol === 1e-8,
    'invalid_input', 'Unexpected tolerances');
  const relative = (a, b) => [(a[0] - b[0]) / scale, (a[1] - b[1]) / scale];
  const edge = (a, b) => relative(row.points[b], row.points[a]);
  const L = (...components) => maximum(components.map(x => Math.abs(x) / lenTol));
  const A = x => Math.abs(x) / angTol;
  const ratios = [];
  let expected;
  if (row.family === 'triangle' || row.family === 'rectangle') {
    expected = [[0, 0], [w, 0]];
  } else expected = [[-w, 0], [w, 0]];
  for (let i = 0; i < 2; i++)
    ratios.push(L(...relative(row.points[i], transformed(t, ...expected[i]))));
  if (row.family === 'triangle') {
    // Circle-intersection oracle uses side lengths, not the solved C or initial C.
    const ac = Math.hypot(w * f, h), bc = Math.hypot(w * (1 - f), h);
    const along = (ac * ac + w * w - bc * bc) / (2 * w);
    expected.push([along, Math.sqrt(ac * ac - along * along)]);
    ratios.push(L(Math.hypot(...edge(0, 2)) - ac), L(Math.hypot(...edge(1, 2)) - bc));
  } else if (row.family === 'rectangle') {
    expected.push([w, h], [0, h]);
    const ab = unit(edge(0, 1)), bc = unit(edge(1, 2)), cd = unit(edge(2, 3)), ad = unit(edge(0, 3));
    ratios.push(A(dot(ab, bc)), L(Math.hypot(...edge(1, 2)) - h),
      A(cross(ab, cd)), L(Math.hypot(...edge(2, 3)) - w), A(cross(bc, ad)));
  } else if (row.family === 'mirror_circles') {
    expected.push([w * f, h], [w * f, -h]);
    const axis = unit(edge(0, 1)), p = edge(0, 2), q = edge(0, 3);
    ratios.push(L(...relative(row.points[2], transformed(t, w * f, h))),
      L(dot(sub(q, p), axis), cross(axis, [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2])),
      L(row.radii[0] / scale - r), L((row.radii[0] - row.radii[1]) / scale));
  } else {
    expected.push([0, r]);
    const axis = unit(edge(0, 1));
    ratios.push(L(row.radii[0] / scale - r),
      L(Math.abs(cross(axis, edge(0, 2))) - row.radii[0] / scale),
      L(Math.hypot(...edge(0, 2)) - Math.hypot(w, r)));
  }
  const independentMaxRatio = maximum(ratios);
  demand(ratios.every(finite) && independentMaxRatio <= 1.00001,
    'independent_residual_violation', `max independent ratio ${independentMaxRatio}`);
  const oracleErrors = expected.flatMap((p, i) =>
    relative(row.points[i], transformed(t, ...p)).map(Math.abs));
  oracleErrors.push(...row.radii.map(x => Math.abs(x / scale - r)));
  const oracleMaxNormalizedError = maximum(oracleErrors);
  demand(oracleMaxNormalizedError <= 50 * lenTol, 'oracle_or_branch_mismatch',
    `max coordinate/radius error divided by scale ${oracleMaxNormalizedError}`);
  demand(row.local_dof === 0 && row.variables === variables && row.equations === equations,
    'dimension_or_dof_mismatch', 'Unexpected variables/equations/DOF');
  demand(Number.isInteger(row.iterations) && row.iterations > 0 && row.iterations <= 200,
    'invalid_output', 'Iteration count');
  demand(Array.isArray(row.residual_ratios) && row.residual_ratios.length === relations &&
    row.residual_ratios.every(x => finite(x) && x >= 0 && x <= 1) &&
    finite(row.max_tolerance_ratio) && row.max_tolerance_ratio <= 1,
  'diagnostic_mismatch', 'Solver reported invalid ratios');
  demand(Math.abs(maximum(row.residual_ratios) - row.max_tolerance_ratio) <= 1e-10 &&
    ratios.every((value, i) => Math.abs(value - row.residual_ratios[i]) <= 0.005),
  'diagnostic_mismatch', 'Independent and solver residuals disagree');
  demand(JSON.stringify(row.points) === JSON.stringify(row.stored_points) &&
    JSON.stringify(row.radii) === JSON.stringify(row.stored_radii),
  'applied_geometry_mismatch', 'Satisfied geometry was not applied');
  return { independent_max_ratio: independentMaxRatio, oracle_max_normalized_error: oracleMaxNormalizedError };
}

const seen = new Set();
for (const row of records) {
  assert.ok(Object.hasOwn(groups, row.group), 'Unknown group');
  assert.ok(Number.isInteger(row.index) && row.index >= 0 && row.index < groups[row.group], 'Case index');
  assert.equal(row.family, families[row.index % 4], 'Model family');
  assert.equal(row.seed, 20261022 + row.index * 37, 'Case seed');
  const id = `${row.group}:${row.index}`;
  assert.ok(!seen.has(id), `Duplicate case ${id}`);
  seen.add(id);
  const expected = expectedInput(row);
  assert.deepEqual(row.parameters, expected.parameters, `${id}: generated dimensions`);
  // Transform/initial-guess comparison permits only cross-runtime math roundoff,
  // not deviations on the scale of the declared perturbation or solve tolerance.
  const nearInput = (a, b) => finite(a) && Math.abs(a - b) <=
    1e-14 * Math.max(Math.abs(b), row.transform.scale);
  for (const key of ['x', 'y', 'angle', 'scale'])
    assert.ok(nearInput(row.transform[key], expected.transform[key]), `${id}: transform ${key}`);
  assert.equal(row.initial_points.length, expected.points.length);
  row.initial_points.forEach((p, i) => p.forEach((v, k) =>
    assert.ok(nearInput(v, expected.points[i][k]), `${id}: initial point ${i}.${k}`)));
  assert.equal(row.initial_radii.length, expected.radii.length);
  row.initial_radii.forEach((v, i) => assert.ok(nearInput(v, expected.radii[i]), `${id}: initial radius ${i}`));
}
for (const [group, count] of Object.entries(groups))
  assert.equal(records.filter(r => r.group === group).length, count);

// Mutation checks exercise the independent checker itself, always on generated
// outputs. A falsely Satisfied result or wrong assembly branch must be rejected.
const selfChecks = [
  ['triangle', r => { r.points[2][0] += r.parameters[0] * r.transform.scale * 0.2; }, 'independent_residual_violation'],
  ['mirror_circles', r => { r.radii[0] = -1; }, 'non_finite_output'],
  ['rectangle', r => {
    const [w, h] = r.parameters;
    r.points = [[0, 0], [w, 0], [w, -h], [0, -h]];
  }, 'oracle_or_branch_mismatch'],
  ['triangle', r => { r.residual_ratios[0] += 0.1; }, 'diagnostic_mismatch'],
  ['triangle', r => { r.local_dof = 1; }, 'dimension_or_dof_mismatch'],
  ['triangle', r => { r.stored_points[0][0] += 1; }, 'applied_geometry_mismatch'],
];
const selected = selection ? records.filter(r => `${r.group}:${r.index}` === selection) : records;
assert.ok(selected.length, `Unknown case ${selection}`);
const outcomes = selected.map(record => {
  try { return { record, passed: true, ...inspect(record) }; }
  catch (error) { return { record, passed: false, category: error.category || 'checker_error', message: error.message }; }
});
const selfCheckResults = selfChecks.map(([family, mutate, category]) => {
  const source = records.find(r => {
    if (r.group !== 'analytic' || r.family !== family) return false;
    try { inspect(r); return true; } catch { return false; }
  });
  if (!source) return { category, passed: false, message: 'No passing control fixture available' };
  const fixture = structuredClone(source);
  mutate(fixture);
  try {
    assert.throws(() => inspect(fixture),
      error => error instanceof ValidationFailure && error.category === category);
    return { category, passed: true };
  } catch (error) { return { category, passed: false, message: error.message }; }
});
const mutationPassed = selfCheckResults.filter(x => x.passed).length;
const sourceFiles = ['cmd/validation/main.mbt', 'cmd/validation/moon.pkg', 'scripts/validation_suite.cjs',
  'scripts/snapshot_provenance.cjs', 'errors.mbt', 'model.mbt', 'validate.mbt', 'residual.mbt', 'solver.mbt', 'autodiff.mbt', 'linalg.mbt'];
const hash = crypto.createHash('sha256');
for (const file of sourceFiles) hash.update(file + '\n' + fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const sourceHash = hash.digest('hex');
const stats = list => {
  const ok = list.filter(x => x.passed);
  const iterations = list.map(x => x.record.iterations).sort((a, b) => a - b);
  const failureCounts = {};
  for (const row of list.filter(x => !x.passed)) failureCounts[row.category] = (failureCounts[row.category] || 0) + 1;
  return { total: list.length, passed: ok.length, failed: list.length - ok.length,
    success_rate: ok.length / list.length, failure_categories: failureCounts,
    iterations: { min: iterations[0], median: iterations[Math.floor(iterations.length / 2)], max: iterations.at(-1) },
    max_independent_tolerance_ratio: maximum(ok.map(x => x.independent_max_ratio)),
    max_oracle_error_divided_by_scale: maximum(ok.map(x => x.oracle_max_normalized_error)) };
};
const summary = {
  schema: 1, corpus: 'cad-validation-400-v1', seed: metadata.seed, target,
  source_sha256: sourceHash, source_files: sourceFiles,
  environment: { platform: process.platform, arch: process.arch, node: process.version, moon: version.stdout.trim() },
  checker_mutation_tests: selfChecks.length, checker_mutation_passed: mutationPassed,
  checker_mutation_failures: selfCheckResults.filter(x => !x.passed), ...stats(outcomes),
  groups: Object.fromEntries(Object.keys(groups).map(group => [group, stats(outcomes.filter(x => x.record.group === group))])),
  families: Object.fromEntries(families.map(family => [family, stats(outcomes.filter(x => x.record.family === family))])),
  failures: outcomes.filter(x => !x.passed).map(x => ({ id: `${x.record.group}:${x.record.index}`,
    family: x.record.family, seed: x.record.seed, category: x.category, message: x.message })),
};
if (selection) {
  console.log(JSON.stringify(outcomes[0], null, 2));
} else {
  fs.writeFileSync(path.join(output, `${target}.json`), JSON.stringify({ summary, outcomes }, null, 2) + '\n');
  const csv = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
  const rows = [['group', 'index', 'family', 'seed', 'status', 'passed', 'failure_category', 'iterations',
    'independent_max_ratio', 'oracle_max_error_divided_by_scale'],
  ...outcomes.map(x => [x.record.group, x.record.index, x.record.family, x.record.seed, x.record.status,
    x.passed, x.category, x.record.iterations, x.independent_max_ratio, x.oracle_max_normalized_error])];
  fs.writeFileSync(path.join(output, `${target}.csv`), rows.map(row => row.map(csv).join(',')).join('\n') + '\n');
  if (write && summary.failed === 0 && mutationPassed === selfChecks.length) {
    const destination = path.join(root, 'docs', 'validation-results', `${target}.json`);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, JSON.stringify(summary, null, 2) + '\n');
  } else if (!write && summary.failed === 0) {
    const snapshot = JSON.parse(fs.readFileSync(path.join(root, 'docs', 'validation-results', `${target}.json`), 'utf8'));
    checkSnapshotSource(snapshot.source_sha256, sourceHash, strictSnapshot);
    assert.equal(snapshot.corpus, summary.corpus);
    assert.equal(snapshot.total, 400);
    assert.equal(snapshot.failed, 0);
  }
  for (const [group, value] of Object.entries(summary.groups))
    console.log(`${target} ${group}: ${value.passed}/${value.total}; independent ratio <= ${value.max_independent_tolerance_ratio}`);
  console.log(`${target}: ${summary.passed}/${summary.total}; checker mutations ${mutationPassed}/${selfChecks.length}; artifacts _build/validation/${target}.*`);
  for (const failure of summary.failures) console.error(JSON.stringify(failure));
  for (const failure of summary.checker_mutation_failures) console.error(JSON.stringify(failure));
}
if (summary.failed || mutationPassed !== selfChecks.length) process.exitCode = 1;
