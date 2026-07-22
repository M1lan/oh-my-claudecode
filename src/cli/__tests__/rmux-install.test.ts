/**
 * Tests for src/cli/rmux-install.ts
 *
 * Covers the install-plan decision ladder and the non-fatal ensure flow:
 *  - rmux already on PATH               → present / already-installed
 *  - ~/mysrc/rmux + cargo               → local-source (cargo install --path)
 *  - cargo-binstall present             → cargo-binstall
 *  - cargo present (no binstall)        → cargo
 *  - nothing available                  → unavailable / skipped (warn, non-fatal)
 *  - install exec success / failure     → installed / failed (never throws)
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { spawnSync } from 'child_process';
import { existsSync } from 'fs';

vi.mock('child_process', async (importOriginal) => {
  const actual = await importOriginal<typeof import('child_process')>();
  return { ...actual, spawnSync: vi.fn() };
});

vi.mock('fs', async (importOriginal) => {
  const actual = await importOriginal<typeof import('fs')>();
  return { ...actual, existsSync: vi.fn() };
});

import {
  detectRmux,
  ensureRmuxInstalled,
  planRmuxInstall,
  rmuxLocalSourcePath,
} from '../rmux-install.js';

const mockedSpawnSync = vi.mocked(spawnSync);
const mockedExistsSync = vi.mocked(existsSync);
const baselinePlatform = process.platform;

function spawnResult(status: number | null, stdout = ''): ReturnType<
  typeof spawnSync
> {
  return {
    status,
    stdout,
    stderr: '',
    pid: 0,
    output: [],
    signal: null,
  } as ReturnType<typeof spawnSync>;
}

/** Route spawnSync results by `bin arg0`, defaulting to a non-zero (absent). */
function routeSpawn(map: Record<string, ReturnType<typeof spawnSync>>): void {
  mockedSpawnSync.mockImplementation(((bin: string, args: string[]) => {
    const key = `${bin} ${args?.[0] ?? ''}`.trim();
    return map[key] ?? spawnResult(1);
  }) as unknown as typeof spawnSync);
}

function setPlatform(platform: NodeJS.Platform): void {
  Object.defineProperty(process, 'platform', {
    value: platform,
    configurable: true,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  setPlatform('linux');
  mockedExistsSync.mockReturnValue(false);
});

afterEach(() => {
  vi.restoreAllMocks();
  setPlatform(baselinePlatform);
});

describe('detectRmux', () => {
  it('reports installed + version when rmux -V succeeds', () => {
    routeSpawn({ 'rmux -V': spawnResult(0, 'rmux 0.9.0\n') });
    expect(detectRmux()).toEqual({ installed: true, version: 'rmux 0.9.0' });
  });

  it('reports absent when rmux -V fails', () => {
    routeSpawn({ 'rmux -V': spawnResult(1) });
    expect(detectRmux()).toEqual({ installed: false, version: null });
  });

  it('is always absent on native Windows (rmux is POSIX-only)', () => {
    setPlatform('win32');
    routeSpawn({ 'rmux -V': spawnResult(0, 'rmux 0.9.0\n') });
    expect(detectRmux()).toEqual({ installed: false, version: null });
  });
});

describe('rmuxLocalSourcePath', () => {
  it('resolves ~/mysrc/rmux when it is a cargo project', () => {
    mockedExistsSync.mockReturnValue(true);
    expect(rmuxLocalSourcePath('/home/u')).toBe('/home/u/mysrc/rmux');
  });

  it('returns null when the directory is absent', () => {
    mockedExistsSync.mockReturnValue(false);
    expect(rmuxLocalSourcePath('/home/u')).toBeNull();
  });

  it('returns null when Cargo.toml is missing', () => {
    mockedExistsSync.mockImplementation(
      (p) => String(p) === '/home/u/mysrc/rmux',
    );
    expect(rmuxLocalSourcePath('/home/u')).toBeNull();
  });
});

describe('planRmuxInstall', () => {
  it('returns present when rmux is already on PATH', () => {
    routeSpawn({ 'rmux -V': spawnResult(0, 'rmux 0.9.0\n') });
    const plan = planRmuxInstall();
    expect(plan.method).toBe('present');
    expect(plan.version).toBe('rmux 0.9.0');
    expect(plan.command).toBeNull();
  });

  it('prefers local source when ~/mysrc/rmux exists and cargo is present', () => {
    mockedExistsSync.mockReturnValue(true);
    routeSpawn({
      'rmux -V': spawnResult(1),
      'cargo --version': spawnResult(0, 'cargo 1.80\n'),
      'cargo-binstall -V': spawnResult(0, 'cargo-binstall 1.0\n'),
    });
    const plan = planRmuxInstall();
    expect(plan.method).toBe('local-source');
    expect(plan.bin).toBe('cargo');
    expect(plan.args?.slice(0, 2)).toEqual(['install', '--path']);
    expect(plan.command).toContain('--path');
    expect(plan.localSourcePath).toContain('mysrc/rmux');
  });

  it('uses cargo-binstall when present and no local source', () => {
    mockedExistsSync.mockReturnValue(false);
    routeSpawn({
      'rmux -V': spawnResult(1),
      'cargo --version': spawnResult(0),
      'cargo-binstall -V': spawnResult(0),
    });
    const plan = planRmuxInstall();
    expect(plan.method).toBe('cargo-binstall');
    expect(plan.bin).toBe('cargo');
    expect(plan.args).toEqual(['binstall', '-y', 'rmux']);
  });

  it('falls back to cargo install when binstall is absent', () => {
    mockedExistsSync.mockReturnValue(false);
    routeSpawn({
      'rmux -V': spawnResult(1),
      'cargo --version': spawnResult(0),
      'cargo-binstall -V': spawnResult(1),
    });
    const plan = planRmuxInstall();
    expect(plan.method).toBe('cargo');
    expect(plan.args).toEqual(['install', 'rmux', '--locked']);
  });

  it('is unavailable when neither cargo nor binstall exist', () => {
    routeSpawn({ 'rmux -V': spawnResult(1) });
    const plan = planRmuxInstall();
    expect(plan.method).toBe('unavailable');
    expect(plan.command).toBeNull();
  });

  it('is unavailable on native Windows', () => {
    setPlatform('win32');
    const plan = planRmuxInstall();
    expect(plan.method).toBe('unavailable');
  });
});

describe('ensureRmuxInstalled', () => {
  it('short-circuits when rmux is already installed', () => {
    routeSpawn({ 'rmux -V': spawnResult(0, 'rmux 0.9.0\n') });
    const logs: string[] = [];
    const result = ensureRmuxInstalled({ log: (m) => logs.push(m) });
    expect(result.status).toBe('already-installed');
    expect(result.version).toBe('rmux 0.9.0');
  });

  it('warns non-fatally with manual instructions when nothing is available', () => {
    routeSpawn({ 'rmux -V': spawnResult(1) });
    const logs: string[] = [];
    const result = ensureRmuxInstalled({ log: (m) => logs.push(m) });
    expect(result.status).toBe('skipped');
    expect(result.method).toBe('unavailable');
    expect(logs.join('\n')).toContain('cargo binstall rmux');
  });

  it('reports installed after a successful cargo-binstall run', () => {
    // Probe order: plan detect (absent) → plan probes → install exec → re-detect.
    mockedSpawnSync
      .mockReturnValueOnce(spawnResult(1)) // rmux -V (plan detect)
      .mockReturnValueOnce(spawnResult(0)) // cargo --version
      .mockReturnValueOnce(spawnResult(0)) // cargo-binstall -V
      .mockReturnValueOnce(spawnResult(0)) // install exec (stdio inherit)
      .mockReturnValueOnce(spawnResult(0, 'rmux 0.9.0\n')); // re-detect
    const logs: string[] = [];
    const result = ensureRmuxInstalled({ log: (m) => logs.push(m) });
    expect(result.status).toBe('installed');
    expect(result.method).toBe('cargo-binstall');
    expect(result.version).toBe('rmux 0.9.0');
  });

  it('reports failed (non-fatal) when the install command exits non-zero', () => {
    mockedSpawnSync
      .mockReturnValueOnce(spawnResult(1)) // rmux -V (plan detect)
      .mockReturnValueOnce(spawnResult(0)) // cargo --version
      .mockReturnValueOnce(spawnResult(1)) // cargo-binstall -V absent
      .mockReturnValueOnce(spawnResult(101)); // cargo install exec fails
    const logs: string[] = [];
    const result = ensureRmuxInstalled({ log: (m) => logs.push(m) });
    expect(result.status).toBe('failed');
    expect(result.method).toBe('cargo');
    expect(logs.join('\n')).toContain('cargo binstall rmux');
  });

  it('does not execute when execute:false — only plans', () => {
    routeSpawn({
      'rmux -V': spawnResult(1),
      'cargo --version': spawnResult(0),
      'cargo-binstall -V': spawnResult(0),
    });
    const result = ensureRmuxInstalled({ execute: false, log: () => {} });
    expect(result.status).toBe('skipped');
    expect(result.method).toBe('cargo-binstall');
    // No install spawn should have been made with stdio: 'inherit'.
    const inheritCalls = mockedSpawnSync.mock.calls.filter(
      (c) => (c[2] as { stdio?: string } | undefined)?.stdio === 'inherit',
    );
    expect(inheritCalls).toHaveLength(0);
  });
});
