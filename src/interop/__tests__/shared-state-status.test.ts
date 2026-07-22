/**
 * Tests for updateInteropStatus: the interop session lifecycle bookkeeping
 * in config.json (active -> completed | failed), including tolerance for a
 * missing or invalid config.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import {
  getInteropDir,
  initInteropSession,
  readInteropConfig,
  updateInteropStatus,
} from '../shared-state.js';

describe('updateInteropStatus', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'interop-status-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('transitions active -> completed', () => {
    initInteropSession('session-1', tempDir);
    expect(readInteropConfig(tempDir)?.status).toBe('active');

    updateInteropStatus(tempDir, 'completed');
    expect(readInteropConfig(tempDir)?.status).toBe('completed');
  });

  it('transitions active -> failed and preserves other config fields', () => {
    const config = initInteropSession('session-2', tempDir, tempDir);

    updateInteropStatus(tempDir, 'failed');

    const updated = readInteropConfig(tempDir);
    expect(updated).toEqual({ ...config, status: 'failed' });
  });

  it('is a silent no-op when config.json is missing', () => {
    expect(() => updateInteropStatus(tempDir, 'failed')).not.toThrow();
    expect(readInteropConfig(tempDir)).toBeNull();
  });

  it('is a silent no-op when config.json is invalid', () => {
    const interopDir = getInteropDir(tempDir);
    mkdirSync(interopDir, { recursive: true });
    writeFileSync(join(interopDir, 'config.json'), 'not json');

    expect(() => updateInteropStatus(tempDir, 'completed')).not.toThrow();
    expect(readInteropConfig(tempDir)).toBeNull();
  });
});
