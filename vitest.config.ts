import path from 'path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['./vitest.setup.ts'],
    // 60s (not 30s): the full ~10k-test suite saturates all fork workers, and
    // disk-heavy skill-loading tests (skills.test.ts reloads ~80 SKILL.md files
    // per test) get scheduler-starved past 30s under that contention. They pass
    // comfortably in isolation; the higher ceiling absorbs load-induced timeout
    // flake without hiding a genuine hang (which still fails, just at 60s).
    testTimeout: 60000,
    include: [
      'src/**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}',
      'tests/**/*.bench.ts',
      'tests/**/*.{test,spec}.ts',
    ],
    exclude: ['node_modules', 'dist', '.omc'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'dist/',
        'src/**/*.{test,spec}.{js,ts}',
        '**/*.d.ts',
        '**/*.config.{js,ts}',
        '**/index.ts',
      ],
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
