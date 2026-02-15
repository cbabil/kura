'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const { loadBrand } = require('../src/utils/brand');

describe('brand.js', () => {
  describe('defaults when brand.env is missing', () => {
    it('returns frozen defaults for non-existent path', () => {
      const brand = loadBrand('/tmp/nonexistent-brand-env-' + Date.now());

      expect(brand.BRAND_NAME).toBe('FalkenOS');
      expect(brand.BRAND_PREFIX).toBe('falken');
      expect(brand.BRAND_VERSION).toBe('2.0');
      expect(brand.BRAND_API_ENDPOINT).toBe('https://api.falken.io');
      expect(brand.BRAND_REGISTRY).toBe('registry.falken.io');
    });

    it('returns a frozen object', () => {
      const brand = loadBrand('/tmp/nonexistent-brand-env-' + Date.now());
      expect(Object.isFrozen(brand)).toBe(true);
    });
  });

  describe('parsing brand.env with custom values', () => {
    let tmpFile;

    beforeEach(() => {
      tmpFile = path.join(os.tmpdir(), `brand-test-${Date.now()}.env`);
    });

    afterEach(() => {
      try { fs.unlinkSync(tmpFile); } catch (_e) { /* ignore */ }
    });

    it('parses double-quoted values', () => {
      fs.writeFileSync(tmpFile, [
        'BRAND_NAME="TestOS"',
        'BRAND_PREFIX="test"',
        'BRAND_VERSION="3.5"',
        'BRAND_API_ENDPOINT="https://api.test.io"',
        'BRAND_REGISTRY="registry.test.io"',
      ].join('\n'));

      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_NAME).toBe('TestOS');
      expect(brand.BRAND_PREFIX).toBe('test');
      expect(brand.BRAND_VERSION).toBe('3.5');
      expect(brand.BRAND_API_ENDPOINT).toBe('https://api.test.io');
      expect(brand.BRAND_REGISTRY).toBe('registry.test.io');
    });

    it('parses single-quoted values', () => {
      fs.writeFileSync(tmpFile, "BRAND_NAME='SingleOS'\n");
      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_NAME).toBe('SingleOS');
    });

    it('parses unquoted values', () => {
      fs.writeFileSync(tmpFile, 'BRAND_PREFIX=mybrand\n');
      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_PREFIX).toBe('mybrand');
    });

    it('ignores comments and blank lines', () => {
      fs.writeFileSync(tmpFile, [
        '# This is a comment',
        '',
        'BRAND_NAME="CommentOS"',
        '   # Another comment',
        '',
      ].join('\n'));

      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_NAME).toBe('CommentOS');
      expect(brand.BRAND_PREFIX).toBe('falken'); // untouched default
    });

    it('ignores unknown keys', () => {
      fs.writeFileSync(tmpFile, [
        'BRAND_NAME="KnownOS"',
        'UNKNOWN_KEY="should-be-ignored"',
      ].join('\n'));

      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_NAME).toBe('KnownOS');
      expect(brand).not.toHaveProperty('UNKNOWN_KEY');
    });

    it('partial override keeps defaults for missing keys', () => {
      fs.writeFileSync(tmpFile, 'BRAND_NAME="PartialOS"\n');
      const brand = loadBrand(tmpFile);
      expect(brand.BRAND_NAME).toBe('PartialOS');
      expect(brand.BRAND_PREFIX).toBe('falken');
      expect(brand.BRAND_VERSION).toBe('2.0');
    });
  });
});
