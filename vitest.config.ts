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
    // Cap fork workers at 50% of cores. Several tests measure the wall-clock of
    // a spawned child process against hard budgets (e.g. COMMAND_CEILING_MS=500
    // in session-end-process-exit.test.ts). At the default (~cores-1 workers)
    // each worker plus its spawned child over-subscribes a high-core dev box,
    // inflating elapsed time past those budgets. Reserving half the cores for
    // child processes keeps a ~1:1 process/core ratio so the budgets hold under
    // the full parallel suite while staying adaptive across machines/CI.
    maxWorkers: '50%',
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
