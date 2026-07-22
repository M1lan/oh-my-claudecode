/**
 * Verification test: ensures no raw rmux/tmux child_process calls exist outside
 * rmux-utils.ts.
 *
 * rmux is the primary multiplexer (tmux is the drop-in fallback), so every raw
 * invocation of either binary must go through the centralized wrappers
 * (rmuxExec, rmuxExecAsync, rmuxShell, rmuxShellAsync, rmuxSpawn, rmuxCmdAsync)
 * defined in src/cli/rmux-utils.ts, which resolve the active multiplexer once.
 * This test enforces that invariant for both binary names. (cmux is a distinct
 * fallback dialect driven separately by the team runtime and is out of scope.)
 */

import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync } from 'fs';
import { join, sep } from 'path';

// Patterns that match raw rmux/tmux calls via child_process functions, for
// both single- and double-quoted binary literals. Matched line-by-line in
// Node so no shell-quoting fragility can silently disable enforcement.
const RAW_CALL_PATTERNS: RegExp[] = [
  /execFileSync\s*\(\s*['"](rmux|tmux)/,
  /execSync\s*\(\s*['"`](rmux|tmux)/,
  /spawnSync\s*\(\s*['"](rmux|tmux)/,
  /execFile\s*\(\s*['"](rmux|tmux)/,
  /\bexec\s*\(\s*[`'"](rmux|tmux)/,
];

function listTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    // Test files legitimately reference the binaries (mocks, fixtures, and
    // this very file's patterns), so they are out of scope.
    if (entry.name === 'node_modules' || entry.name === '__tests__') continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listTsFiles(full));
    } else if (entry.isFile() && full.endsWith('.ts')) {
      out.push(full);
    }
  }
  return out;
}

function grepForRawMultiplexerCalls(): string[] {
  const srcDir = join(__dirname, '..', '..');
  // The centralized wrappers legitimately invoke the binaries directly.
  const wrapperFile = join('cli', 'rmux-utils.ts');
  const violations: string[] = [];
  for (const file of listTsFiles(srcDir)) {
    if (file.endsWith(sep + wrapperFile)) continue;
    const lines = readFileSync(file, 'utf-8').split('\n');
    lines.forEach((line, index) => {
      const content = line.trim();
      // Skip comment lines.
      if (content.startsWith('*') || content.startsWith('//')) return;
      if (RAW_CALL_PATTERNS.some((pattern) => pattern.test(line))) {
        violations.push(`${file}:${index + 1}: ${content}`);
      }
    });
  }
  return violations;
}

describe('rmux/tmux call centralization', () => {
  it('has zero raw rmux/tmux child_process calls outside rmux-utils.ts and test files', () => {
    const violations = grepForRawMultiplexerCalls();
    if (violations.length > 0) {
      const formatted = violations.map((v: string) => `  ${v}`).join('\n');
      expect.fail(
        `Found ${violations.length} raw rmux/tmux call(s) outside rmux-utils.ts:\n${formatted}\n\n` +
          'All rmux/tmux calls must use the centralized wrappers (rmuxExec, rmuxExecAsync, etc.) from src/cli/rmux-utils.ts.',
      );
    }
    expect(violations).toHaveLength(0);
  });
});
