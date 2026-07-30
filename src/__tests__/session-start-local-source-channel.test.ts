import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const SCRIPT_PATH = join(__dirname, '..', '..', 'scripts', 'session-start.mjs');
const NODE = process.execPath;

/**
 * A local checkout is governed by git, so the npm registry is not an actionable
 * update channel for it. Advertising a registry release there points the user at
 * an install that would overwrite their own build.
 */
describe('session-start.mjs local-source update channel', () => {
  let tempDir: string;
  let fakeHome: string;
  let fakeProject: string;
  let claudeDir: string;
  let checkoutRoot: string;

  const writeCheckout = (version: string) => {
    mkdirSync(join(checkoutRoot, '.claude-plugin'), { recursive: true });
    mkdirSync(join(checkoutRoot, '.git'), { recursive: true });
    writeFileSync(
      join(checkoutRoot, 'package.json'),
      JSON.stringify({
        name: 'oh-my-claude-sisyphus',
        version,
        type: 'module',
      }),
    );
    writeFileSync(
      join(checkoutRoot, '.claude-plugin', 'marketplace.json'),
      JSON.stringify({
        name: 'omc',
        plugins: [{ name: 'oh-my-claudecode', version }],
        version,
      }),
    );
  };

  const writeStaleNpmCache = () => {
    mkdirSync(join(claudeDir, '.omc'), { recursive: true });
    writeFileSync(
      join(claudeDir, '.omc', 'update-check.json'),
      JSON.stringify({
        timestamp: Date.now(),
        latestVersion: '9.9.9',
        currentVersion: '4.15.6',
        updateAvailable: true,
        source: 'npm',
      }),
    );
  };

  const runHook = (sessionId: string) =>
    spawnSync(NODE, [SCRIPT_PATH], {
      input: JSON.stringify({
        hook_event_name: 'SessionStart',
        session_id: sessionId,
        cwd: fakeProject,
      }),
      encoding: 'utf-8',
      env: {
        ...process.env,
        HOME: fakeHome,
        USERPROFILE: fakeHome,
        CLAUDE_CONFIG_DIR: claudeDir,
        CLAUDE_PLUGIN_ROOT: checkoutRoot,
        OMC_NOTIFY: '0',
      },
      timeout: 15000,
    });

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'omc-session-start-local-source-'));
    fakeHome = join(tempDir, 'home');
    fakeProject = join(tempDir, 'project');
    claudeDir = join(fakeHome, '.claude');
    checkoutRoot = join(tempDir, 'checkout');
    mkdirSync(join(fakeProject, '.git'), { recursive: true });
    mkdirSync(join(claudeDir, 'plugins'), { recursive: true });
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('suppresses the npm update notice for a directory-source marketplace install', () => {
    writeCheckout('4.15.6');
    writeStaleNpmCache();
    writeFileSync(
      join(claudeDir, 'plugins', 'known_marketplaces.json'),
      JSON.stringify({
        omc: {
          source: { source: 'directory', path: checkoutRoot },
          installLocation: checkoutRoot,
        },
      }),
    );

    const result = runHook('session-local-source-directory');

    expect(result.status).toBe(0);
    const output = JSON.parse(result.stdout) as { systemMessage?: string };
    expect(output.systemMessage ?? '').not.toContain('[OMC UPDATE AVAILABLE]');

    const cache = JSON.parse(
      readFileSync(join(claudeDir, '.omc', 'update-check.json'), 'utf-8'),
    ) as { source?: string; updateAvailable?: boolean };
    expect(cache.source).toBe('local-source');
    expect(cache.updateAvailable).toBe(false);
  });

  it('suppresses the npm update notice for an unregistered checkout plugin root', () => {
    writeCheckout('4.15.6');
    writeStaleNpmCache();

    const result = runHook('session-local-source-checkout');

    expect(result.status).toBe(0);
    const output = JSON.parse(result.stdout) as { systemMessage?: string };
    expect(output.systemMessage ?? '').not.toContain('[OMC UPDATE AVAILABLE]');

    const cache = JSON.parse(
      readFileSync(join(claudeDir, '.omc', 'update-check.json'), 'utf-8'),
    ) as { source?: string };
    expect(cache.source).toBe('local-source');
  });

  it('still reports npm updates when the plugin root is not a local checkout', () => {
    // No .git and no marketplace registration: an ordinary unmanaged install.
    mkdirSync(checkoutRoot, { recursive: true });
    writeFileSync(
      join(checkoutRoot, 'package.json'),
      JSON.stringify({
        name: 'oh-my-claude-sisyphus',
        version: '4.15.6',
        type: 'module',
      }),
    );
    writeStaleNpmCache();

    const result = runHook('session-npm-channel');

    expect(result.status).toBe(0);
    const output = JSON.parse(result.stdout) as { systemMessage?: string };
    expect(output.systemMessage ?? '').toContain('[OMC UPDATE AVAILABLE]');
    expect(output.systemMessage ?? '').toContain('v9.9.9');
  });
});
