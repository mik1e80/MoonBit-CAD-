'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
let target = 'js', write = false, smoke = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--write') write = true;
  else if (args[i] === '--check') assert.ok(!args.includes('--write'), 'Choose --write or --check');
  else if (args[i] === '--smoke') smoke = true;
  else if (args[i] === '--target') target = args[++i];
  else throw new Error('Usage: node scripts/benchmark.cjs [--check | --write] [--smoke] [--target js|wasm|wasm-gc|native]');
}
assert.ok(['js', 'wasm', 'wasm-gc', 'native'].includes(target));
assert.ok(!smoke || !write, 'Smoke data cannot replace a full benchmark snapshot');
const moon = process.env.MOON_HOME
  ? path.join(process.env.MOON_HOME, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon')
  : (process.platform === 'win32' ? 'moon.exe' : 'moon');
const version = spawnSync(moon, ['version', '--all'], { cwd: root, encoding: 'utf8', timeout: 30_000 });
assert.equal(version.status, 0, version.stderr || version.error?.message);
const run = spawnSync(moon, ['run', 'bench', '--target', target, '--release', '--deny-warn'], {
  cwd: root, encoding: 'utf8', timeout: 180_000, maxBuffer: 16 * 1024 * 1024,
  env: { ...process.env, CAD_SKETCH_BENCH_SMOKE: smoke ? '1' : '0' },
});
const output = path.join(root, '_build', 'bench');
fs.mkdirSync(output, { recursive: true });
const suffix = target + (smoke ? '-smoke' : '');
fs.writeFileSync(path.join(output, suffix + '.jsonl'), run.stdout || '');
fs.writeFileSync(path.join(output, suffix + '.stderr.log'), (run.stderr || '') + (run.error?.stack || ''));
assert.equal(run.status, 0, run.stderr || run.error?.message);
const [metadata, ...records] = run.stdout.trim().split(/\r?\n/).map(JSON.parse);
const repetitions = smoke ? 1 : 3, warmups = smoke ? 0 : 1;
assert.deepEqual(metadata, { kind: 'cad_sketch_benchmark', schema: 1, smoke, warmups, repetitions, length_tolerance: 1e-7 });
const sizes = smoke ? { Small: 10 } : { Small: 10, Medium: 30, Large: 60, Stress: 100 };
assert.equal(records.length, Object.keys(sizes).length * repetitions);
const finite = x => typeof x === 'number' && Number.isFinite(x);
const maximum = values => Math.max(0, ...values);
const targetPoint = i => [i, i % 2 ? 2 : 0];
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
function initial(count) {
  let seed = 20261022 + count * 31;
  const draw = () => {
    const value = 16807 * (seed % 127773) - 2836 * Math.floor(seed / 127773);
    seed = value > 0 ? value : value + 2147483647;
    return seed / 2147483647;
  };
  for (let i = 0; i < 5; i++) draw();
  return Array.from({ length: count }, (_, i) => targetPoint(i).map(x => x + 0.05 * (2 * draw() - 1)));
}
function inspect(row) {
  const n = sizes[row.case_name], tol = metadata.length_tolerance;
  assert.ok(n, 'Unknown workload');
  assert.equal(row.point_count, n);
  assert.equal(row.constraint_count, 2 * n);
  assert.equal(row.seed, 20261022 + n * 31);
  assert.deepEqual(row.initial_points, initial(n), 'Initial guess changed');
  assert.deepEqual(row.retained_points, row.initial_points, 'solve() changed stored geometry');
  assert.deepEqual(row.warmup_statuses, Array(warmups).fill('Satisfied'), 'Warmup failed');
  assert.ok(finite(row.elapsed_us) && row.elapsed_us > 0, 'Invalid clock result');
  assert.equal(row.status, 'Satisfied', row.error || row.status);
  assert.equal(row.variables, n * 2);
  assert.equal(row.equations, n * 2 + 2);
  assert.equal(row.local_dof, 0);
  assert.equal(row.dependent_equations, 2);
  assert.ok(Number.isInteger(row.iterations) && row.iterations > 0 && row.iterations <= 200);
  const p = row.points;
  assert.ok(Array.isArray(p) && p.length === n && p.every(q => Array.isArray(q) && q.length === 2 && q.every(finite)));
  const errors = [0, 1].map(i => maximum(p[i].map((v, axis) => Math.abs(v - targetPoint(i)[axis]))));
  for (let i = 1; i < n; i++) errors.push(Math.abs(distance(p[i - 1], p[i]) - Math.sqrt(5)));
  for (let i = 2; i < n; i++) errors.push(Math.abs(distance(p[i - 2], p[i]) - 2));
  errors.push(Math.abs(distance(p[0], p.at(-1)) - distance(targetPoint(0), targetPoint(n - 1))));
  assert.equal(errors.length, n * 2);
  const independentRatio = maximum(errors) / tol;
  assert.ok(independentRatio <= 1.00001, 'Independent residual exceeds tolerance');
  assert.equal(row.residual_ratios.length, errors.length);
  assert.ok(row.residual_ratios.every((ratio, i) => finite(ratio) && ratio >= 0 && ratio <= 1 &&
    Math.abs(ratio - errors[i] / tol) <= 1e-5), 'Per-constraint diagnostics disagree');
  assert.ok(finite(row.max_length_error) && row.max_length_error <= tol &&
    Math.abs(row.max_length_error - maximum(errors)) <= 1e-12, 'Wrong maximum residual');
  assert.ok(Math.abs(row.max_tolerance_ratio - independentRatio) <= 1e-5 &&
    row.max_tolerance_ratio <= 1, 'Wrong maximum tolerance ratio');
  const coordinateError = maximum(p.flatMap((point, i) => point.map((v, axis) => Math.abs(v - targetPoint(i)[axis]))));
  assert.ok(coordinateError <= 50 * n * tol, 'Wrong assembly or accumulated coordinate drift');
  for (let i = 2; i < n; i++) {
    const a = p[i - 2], b = p[i - 1], c = p[i];
    const cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
    assert.ok((i % 2 ? cross : -cross) > 0, 'Triangle assembly flipped');
  }
  return { independent_max_length_error: maximum(errors), independent_max_ratio: independentRatio, coordinate_max_error: coordinateError };
}
const seen = new Set();
const outcomes = records.map(record => {
  const id = record.case_name + ':' + record.repetition;
  assert.ok(Number.isInteger(record.repetition) && record.repetition >= 0 && record.repetition < repetitions && !seen.has(id));
  seen.add(id);
  try { return { record, passed: true, ...inspect(record) }; }
  catch (error) { return { record, passed: false, error: error.message }; }
});
// Directed checker controls: corrupted geometry, dimensions or solve side effect.
const fixture = outcomes.find(x => x.passed)?.record;
const mutations = [r => { r.points[2][0] += 1; }, r => { r.constraint_count--; }, r => { r.retained_points[0][0] += 1; }];
let mutationPassed = 0;
if (fixture) for (const mutate of mutations) {
  const copy = structuredClone(fixture);
  mutate(copy);
  assert.throws(() => inspect(copy));
  mutationPassed++;
}
const sourceFiles = ['bench/main.mbt', 'bench/moon.pkg', 'scripts/benchmark.cjs',
  'model.mbt', 'solver.mbt', 'validate.mbt', 'residual.mbt', 'autodiff.mbt', 'linalg.mbt'];
const digest = crypto.createHash('sha256');
for (const name of sourceFiles) digest.update(name + '\n' + fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n'));
const range = values => {
  const sorted = [...values].sort((a, b) => a - b);
  return { min: sorted[0], median: sorted[Math.floor(sorted.length / 2)], max: sorted.at(-1) };
};
const cases = Object.entries(sizes).map(([name, n]) => {
  const items = outcomes.filter(x => x.record.case_name === name), ok = items.filter(x => x.passed);
  assert.equal(items.length, repetitions);
  return { case: name, points: n, variables: n * 2, constraints: n * 2, equations: n * 2 + 2,
    repetitions, verified_successes: ok.length, reported_status_counts: Object.fromEntries(
      [...new Set(items.map(x => x.record.status))].map(s => [s, items.filter(x => x.record.status === s).length])),
    iterations: range(items.map(x => x.record.iterations)), solve_us: range(items.map(x => x.record.elapsed_us)),
    max_independent_length_error: maximum(ok.map(x => x.independent_max_length_error)),
    max_tolerance_ratio: maximum(ok.map(x => x.independent_max_ratio)),
    max_coordinate_error: maximum(ok.map(x => x.coordinate_max_error)) };
});
const summary = { schema: 1, workload: 'triangulated-zigzag-v1', target, build: 'release', smoke,
  warmups_per_case: warmups, repetitions_per_case: repetitions, length_tolerance: 1e-7, cases,
  measured_solves: outcomes.length, verified_successes: outcomes.filter(x => x.passed).length, checker_mutations_passed: mutationPassed,
  failures: outcomes.filter(x => !x.passed).map(x => ({ case: x.record.case_name, repetition: x.record.repetition, status: x.record.status, error: x.error })),
  source_files: sourceFiles, source_sha256: digest.digest('hex'),
  environment: { platform: process.platform, release: os.release(), arch: os.arch(), cpu: os.cpus()[0]?.model,
    logical_cpus: os.cpus().length, memory_bytes: os.totalmem(), node: process.version, moon: version.stdout.trim() } };
const cell = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
const csv = [['case', 'points', 'variables', 'constraints', 'equations', 'repetition', 'seed', 'status',
  'iterations', 'solve_us', 'independent_max_length_error', 'independent_max_ratio', 'coordinate_max_error', 'passed',
  'initial_points', 'result_points', 'error'],
...outcomes.map(x => { const r = x.record; return [r.case_name, r.point_count, r.variables, r.constraint_count, r.equations,
  r.repetition, r.seed, r.status, r.iterations, r.elapsed_us, x.independent_max_length_error, x.independent_max_ratio,
  x.coordinate_max_error, x.passed, JSON.stringify(r.initial_points), JSON.stringify(r.points), x.error]; })]
  .map(row => row.map(cell).join(',')).join('\n') + '\n';
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
summary.cases_csv_sha256 = hash(csv);
fs.writeFileSync(path.join(output, suffix + '.json'), JSON.stringify({ summary, outcomes }, null, 2) + '\n');
fs.writeFileSync(path.join(output, suffix + '.csv'), csv);
const healthy = !summary.failures.length && mutationPassed === mutations.length;
const folder = path.join(root, 'docs', 'benchmarks');
if (write && healthy) {
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, target + '.json'), JSON.stringify(summary, null, 2) + '\n');
  fs.writeFileSync(path.join(folder, target + '.csv'), csv);
} else if (!write && !smoke && healthy) {
  const snapshot = JSON.parse(fs.readFileSync(path.join(folder, target + '.json'), 'utf8'));
  assert.equal(snapshot.source_sha256, summary.source_sha256, 'Stale benchmark snapshot: review results and --write');
  assert.equal(snapshot.cases_csv_sha256, hash(fs.readFileSync(path.join(folder, target + '.csv'), 'utf8').replace(/\r\n/g, '\n')));
  // No timing threshold and no cross-machine equality assertions.
}
for (const c of cases) console.log(`${c.case}: vars=${c.variables} constraints=${c.constraints} iterations=${c.iterations.median} success=${c.verified_successes}/${repetitions} max_residual=${c.max_independent_length_error} solve_median_us=${c.solve_us.median}`);
console.log(`Checker controls ${mutationPassed}/${mutations.length}; raw results _build/bench/${suffix}.*`);
if (!healthy) { console.error(JSON.stringify(summary.failures, null, 2)); process.exitCode = 1; }
