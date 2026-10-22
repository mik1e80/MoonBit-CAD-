'use strict';
const assert = require('node:assert/strict');

// A fresh run validates its own results. A published snapshot is separate,
// historical evidence and must never be relabelled as a run of new sources.
function checkSnapshotSource(snapshotHash, currentHash, strict, warn = console.warn) {
  const current = snapshotHash === currentHash;
  if (strict) assert.ok(current, 'Historical snapshot: review a new full run before --write');
  if (!current) warn(`Historical snapshot (${snapshotHash}); current sources ${currentHash}. Fresh results are checked independently; committed measurements were not refreshed.`);
  return current;
}
module.exports = { checkSnapshotSource };
