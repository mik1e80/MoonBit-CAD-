'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
let target = 'js', write = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--write') write = true;
  else if (args[i] === '--check') assert.ok(!args.includes('--write'), 'Choose --write or --check');
  else if (args[i] === '--target') target = args[++i];
  else throw new Error('Usage: node scripts/random_triangle.cjs [--check | --write] [--target js|wasm|wasm-gc|native]');
}
assert.ok(['js', 'wasm', 'wasm-gc', 'native'].includes(target));
const moon = process.env.MOON_HOME
  ? path.join(process.env.MOON_HOME, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon')
  : (process.platform === 'win32' ? 'moon.exe' : 'moon');
const version = spawnSync(moon, ['version', '--all'], { cwd: root, encoding: 'utf8', timeout: 30_000 });
assert.equal(version.status, 0, version.stderr || version.error?.message);
const run = spawnSync(moon, ['run', 'cmd/random_triangle', '--target', target], {
  cwd: root, encoding: 'utf8', timeout: 120_000, maxBuffer: 16 * 1024 * 1024,
});
const output = path.join(root, '_build', 'random-triangle');
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, `${target}.jsonl`), run.stdout || '');
fs.writeFileSync(path.join(output, `${target}.stderr.log`), (run.stderr || '') + (run.error?.stack || ''));
assert.equal(run.status, 0, run.stderr || run.error?.message);
const [metadata, ...records] = run.stdout.trim().split(/\r?\n/).map(JSON.parse);
assert.deepEqual(metadata, {
  kind: 'random_triangle', schema: 1, cases: 1000, seed: 20261022, seed_step: 97,
  warmup: 5, coordinate_range: [-10, 10], sides: [3, 4, 5], length_tolerance: 1e-7, max_iterations: 200,
});
assert.equal(records.length, 1000);
function prng(seed) {
  return () => {
    const value = 16807 * (seed % 127773) - 2836 * Math.floor(seed / 127773);
    seed = value > 0 ? value : value + 2147483647;
    return seed / 2147483647;
  };
}
const finite = x => typeof x === 'number' && Number.isFinite(x);
const validPoints = points => Array.isArray(points) && points.length === 3 &&
  points.every(p => Array.isArray(p) && p.length === 2 && p.every(finite));
const equalPoints = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const statuses = ['Satisfied', 'Stalled', 'IterationLimit', 'Invalid'];
function inspect(row) {
  const failures = [];
  const require = (value, category) => { if (!value) failures.push(category); };
  require(statuses.includes(row.status), 'unknown_status');
  require(validPoints(row.initial_points) && validPoints(row.stored_points), 'non_finite_stored_or_initial');
  if (row.status === 'Invalid') {
    require(typeof row.error === 'string' && row.error.length > 0, 'missing_error');
    require(equalPoints(row.stored_points, row.initial_points), 'failed_geometry_changed');
    return { failures, edges: null, independent_max_ratio: null };
  }
  require(validPoints(row.points), 'non_finite_output');
  require(Number.isInteger(row.iterations) && row.iterations >= 0 && row.iterations <= 200, 'invalid_iterations');
  require(row.variables === 6 && row.equations === 3, 'wrong_dimensions');
  require(Array.isArray(row.residual_ratios) && row.residual_ratios.length === 3 &&
    row.residual_ratios.every(x => finite(x) && x >= 0), 'invalid_residuals');
  require(finite(row.max_tolerance_ratio) && row.max_tolerance_ratio >= 0, 'invalid_max_ratio');
  if (!validPoints(row.points)) return { failures, edges: null, independent_max_ratio: null };
  const edges = [[0, 1], [1, 2], [0, 2]].map(([a, b]) =>
    Math.hypot(row.points[a][0] - row.points[b][0], row.points[a][1] - row.points[b][1]));
  const ratios = edges.map((value, i) => Math.abs(value - metadata.sides[i]) / metadata.length_tolerance);
  const independent = Math.max(...ratios);
  require(ratios.every(finite), 'non_finite_edge_error');
  require(ratios.every((ratio, i) => Math.abs(ratio - row.residual_ratios[i]) <= 1e-5) &&
    Math.abs(independent - row.max_tolerance_ratio) <= 1e-5, 'diagnostic_mismatch');
  if (row.status === 'Satisfied') {
    require(independent <= 1.00001, 'false_satisfaction');
    require(row.local_dof === 3, 'wrong_satisfied_dof');
    require(equalPoints(row.stored_points, row.points), 'success_not_applied');
  } else require(equalPoints(row.stored_points, row.initial_points), 'failed_geometry_changed');
  return { failures, edges, independent_max_ratio: independent };
}
for (const [index, row] of records.entries()) {
  assert.equal(row.index, index, 'Missing, reordered or repeated sample');
  assert.equal(row.seed, 20261022 + index * 97);
  const draw = prng(row.seed);
  for (let j = 0; j < 5; j++) draw();
  const initial = Array.from({ length: 3 }, () => [20 * draw() - 10, 20 * draw() - 10]);
  assert.deepEqual(row.initial_points, initial, `Sample ${index}: altered random initial coordinates`);
}
const outcomes = records.map(record => ({ record, ...inspect(record) }));
const counts = Object.fromEntries(statuses.map(status => [status, records.filter(r => r.status === status).length]));
const verifiedSatisfied = outcomes.filter(x => x.record.status === 'Satisfied' && !x.failures.length);
// A separate exact control keeps checker tests independent of the observed
// convergence rate: even 0/1000 successes must still be reportable honestly.
const fixture = verifiedSatisfied[0]?.record || {
  initial_points: [[-2, -1], [-2, 4], [6, -8]],
  points: [[0, 0], [3, 0], [3, 4]], stored_points: [[0, 0], [3, 0], [3, 4]],
  status: 'Satisfied', error: '', iterations: 0, variables: 6, equations: 3,
  local_dof: 3, max_tolerance_ratio: 0, residual_ratios: [0, 0, 0],
};
const mutations = [
  ['false_satisfaction', r => { r.points[0][0] += 2; }],
  ['non_finite_output', r => { r.points[1][0] = NaN; }],
  ['failed_geometry_changed', r => { r.status = 'Stalled'; }],
];
const mutationResults = mutations.map(([category, mutate]) => {
  const copy = structuredClone(fixture);
  mutate(copy);
  return { category, passed: inspect(copy).failures.includes(category) };
});
const sourceFiles = ['cmd/random_triangle/main.mbt', 'cmd/random_triangle/moon.pkg', 'scripts/random_triangle.cjs',
  'model.mbt', 'solver.mbt', 'validate.mbt', 'residual.mbt', 'autodiff.mbt', 'linalg.mbt'];
const digest = crypto.createHash('sha256');
for (const file of sourceFiles) digest.update(file + '\n' +
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const iterations = records.filter(r => r.status !== 'Invalid').map(r => r.iterations).sort((a, b) => a - b);
const correctnessFailures = outcomes.filter(x => x.failures.length).map(x =>
  ({ index: x.record.index, seed: x.record.seed, status: x.record.status, failures: x.failures }));
const csvCell = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
const csvRows = [['index', 'seed', 'status', 'iterations', 'initial_points', 'candidate_points', 'stored_points',
  'AB', 'BC', 'AC', 'independent_max_ratio', 'reported_max_ratio', 'local_dof', 'correctness_failures', 'error'],
...outcomes.map(x => [x.record.index, x.record.seed, x.record.status, x.record.iterations,
  JSON.stringify(x.record.initial_points), JSON.stringify(x.record.points), JSON.stringify(x.record.stored_points),
  ...(x.edges || [null, null, null]), x.independent_max_ratio, x.record.max_tolerance_ratio,
  x.record.local_dof, x.failures.join('|'), x.record.error])];
const csv = csvRows.map(row => row.map(csvCell).join(',')).join('\n') + '\n';
const sha = text => crypto.createHash('sha256').update(text).digest('hex');
const summary = {
  schema: 1, experiment: '3-4-5-triangle-random-initialization-v1', target, cases: records.length,
  seed: metadata.seed, seed_step: 97, warmup: 5, coordinate_range: [-10, 10], sides: [3, 4, 5],
  length_tolerance: 1e-7, max_iterations: 200, anchors: false, expected_local_dof: 3,
  restarts_per_case: 0, counts, independently_verified_satisfied: verifiedSatisfied.length,
  verified_satisfaction_rate: verifiedSatisfied.length / records.length,
  correctness_failures: correctnessFailures, checker_mutations: mutationResults,
  invalid_cases: records.filter(r => r.status === 'Invalid').map(r => ({ index: r.index, seed: r.seed, error: r.error })),
  nonconverged_cases: records.filter(r => ['Stalled', 'IterationLimit'].includes(r.status))
    .map(r => ({ index: r.index, seed: r.seed, status: r.status, iterations: r.iterations,
      max_tolerance_ratio: r.max_tolerance_ratio })),
  iterations: { min: iterations[0], median: iterations[Math.floor(iterations.length / 2)], max: iterations.at(-1) },
  max_verified_tolerance_ratio: Math.max(0, ...verifiedSatisfied.map(x => x.independent_max_ratio)),
  source_sha256: digest.digest('hex'), source_files: sourceFiles, cases_csv_sha256: sha(csv),
  environment: { platform: process.platform, arch: process.arch, node: process.version, moon: version.stdout.trim() },
};
fs.writeFileSync(path.join(output, `${target}.json`), JSON.stringify({ summary, outcomes }, null, 2) + '\n');
fs.writeFileSync(path.join(output, `${target}.csv`), csv);
const healthy = !correctnessFailures.length && mutationResults.every(x => x.passed);
const snapshotPath = path.join(root, 'docs', 'validation-results', `random-triangle-${target}.json`);
const csvPath = path.join(root, 'docs', 'validation-results', `random-triangle-${target}.csv`);
if (write && healthy) {
  fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
  fs.writeFileSync(snapshotPath, JSON.stringify(summary, null, 2) + '\n');
  fs.writeFileSync(csvPath, csv);
} else if (!write && healthy) {
  const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
  assert.equal(snapshot.source_sha256, summary.source_sha256, 'Stale experiment snapshot; review and regenerate --write');
  assert.equal(snapshot.cases, 1000);
  assert.deepEqual(snapshot.sides, [3, 4, 5]);
  assert.equal(sha(fs.readFileSync(csvPath, 'utf8').replace(/\r\n/g, '\n')), snapshot.cases_csv_sha256,
    'Committed per-case CSV does not match its snapshot');
}
console.log(JSON.stringify({
  target, cases: records.length, counts, independently_verified_satisfied: verifiedSatisfied.length,
  correctness_failures: correctnessFailures.length, checker_mutations_passed: mutationResults.filter(x => x.passed).length,
  iterations: summary.iterations, max_verified_tolerance_ratio: summary.max_verified_tolerance_ratio,
}, null, 2));
console.log(`Raw cases and checks: _build/random-triangle/${target}.*`);
if (!healthy) {
  console.error(JSON.stringify({ correctnessFailures, mutationResults }, null, 2));
  process.exitCode = 1;
}
