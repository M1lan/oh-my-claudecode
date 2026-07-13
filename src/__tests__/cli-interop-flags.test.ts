import { describe, expect, it } from 'vitest';
import {
  readInteropRuntimeFlags,
  validateInteropRuntimeFlags,
  INTEROP_CAVEMAN_LEVEL_ENV,
  INTEROP_CAVEMAN_LEVEL,
  INTEROP_CAVEMAN_ACTIVATION,
} from '../cli/interop.js';

describe('cli interop flag validation', () => {
  it('reads defaults', () => {
    const flags = readInteropRuntimeFlags({} as NodeJS.ProcessEnv);
    expect(flags.enabled).toBe(false);
    expect(flags.mode).toBe('off');
    expect(flags.omcInteropToolsEnabled).toBe(false);
    expect(flags.failClosed).toBe(true);
  });

  it('rejects non-off mode when interop is disabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '0',
      OMX_OMC_INTEROP_MODE: 'observe',
      OMC_INTEROP_TOOLS_ENABLED: '0',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toContain('must be "off"');
  });

  it('rejects active mode without interop tools enabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '1',
      OMX_OMC_INTEROP_MODE: 'active',
      OMC_INTEROP_TOOLS_ENABLED: '0',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toContain('OMC_INTEROP_TOOLS_ENABLED=1');
  });

  it('accepts active mode when required flags are enabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '1',
      OMX_OMC_INTEROP_MODE: 'active',
      OMC_INTEROP_TOOLS_ENABLED: '1',
      OMX_OMC_INTEROP_FAIL_CLOSED: '1',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(true);
  });
});

// Cross-repo contract: oh-my-codex reads OMX_INTEROP_CAVEMAN_LEVEL and matches on
// the `use caveman <level> mode` string. Lock both so a rename on one side is
// caught here rather than silently breaking OMX's interop caveman activation.
describe('interop caveman activation contract', () => {
  it('exports the env var name oh-my-codex reads', () => {
    expect(INTEROP_CAVEMAN_LEVEL_ENV).toBe('OMX_INTEROP_CAVEMAN_LEVEL');
  });

  it('uses wenyan-ultra as the interop level', () => {
    expect(INTEROP_CAVEMAN_LEVEL).toBe('wenyan-ultra');
  });

  it('builds the caveman skill activation string', () => {
    expect(INTEROP_CAVEMAN_ACTIVATION).toBe('use caveman wenyan-ultra mode');
  });
});
