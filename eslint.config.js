const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig([
  expoConfig,
  { ignores: ['dist/**', '.expo/**'] },
  {
    files: ['**/*.test.ts'],
    rules: { 'import/no-nodejs-modules': 'off' },
  },
]);
