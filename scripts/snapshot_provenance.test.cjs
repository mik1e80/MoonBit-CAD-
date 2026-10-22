'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { checkSnapshotSource } = require('./snapshot_provenance.cjs');

test('matching snapshot is current and silent', () => {
  assert.equal(checkSnapshotSource('same', 'same', true, () => assert.fail('unexpected warning')), true);
});
test('fresh checks explicitly identify historical evidence without altering it', () => {
  const warnings = [];
  assert.equal(checkSnapshotSource('old', 'new', false, text => warnings.push(text)), false);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /Historical snapshot \(old\); current sources new/);
});
test('strict provenance still rejects stale snapshots', () => {
  assert.throws(() => checkSnapshotSource('old', 'new', true), /Historical snapshot/);
});
