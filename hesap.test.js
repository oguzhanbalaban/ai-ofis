'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { topla, cikar } = require('./hesap');

test('topla', () => {
  assert.strictEqual(topla(2, 3), 5);
});

test('cikar', () => {
  assert.strictEqual(cikar(5, 3), 2);
});
