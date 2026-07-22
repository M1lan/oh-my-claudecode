import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { execFile } from 'child_process';
import {
  canUseOmxDirectWriteBridge,
  getInteropMode,
  interopReadMessagesTool,
  interopReadResultsTool,
  interopSendMessageTool,
  interopSendOmxMessageTool,
  interopSendTaskTool,
} from '../mcp-bridge.js';
import {
  initInteropSession,
  readSharedMessages,
  readSharedTasks,
  updateSharedTask,
} from '../shared-state.js';

vi.mock('child_process', () => ({
  execFile: vi.fn(),
}));

type ExecFileError = Error & { code?: string | number };

type ExecFileCallback = (
  error: ExecFileError | null,
  stdout: string,
  stderr: string,
) => void;

const execFileMock = vi.mocked(execFile) as unknown as ReturnType<typeof vi.fn>;

function mockOmxCliResult(result: {
  error?: ExecFileError | null;
  stdout?: string;
  stderr?: string;
}) {
  execFileMock.mockImplementation(
    (
      _cmd: string,
      _args: string[],
      _options: unknown,
      callback: ExecFileCallback,
    ) => {
      callback(result.error ?? null, result.stdout ?? '', result.stderr ?? '');
      return {} as never;
    },
  );
}

describe('interop mcp bridge gating', () => {
  it('getInteropMode normalizes invalid values to off', () => {
    expect(
      getInteropMode({ OMX_OMC_INTEROP_MODE: 'ACTIVE' } as NodeJS.ProcessEnv),
    ).toBe('active');
    expect(
      getInteropMode({ OMX_OMC_INTEROP_MODE: 'observe' } as NodeJS.ProcessEnv),
    ).toBe('observe');
    expect(
      getInteropMode({ OMX_OMC_INTEROP_MODE: 'nonsense' } as NodeJS.ProcessEnv),
    ).toBe('off');
  });

  it('canUseOmxDirectWriteBridge requires all active flags', () => {
    expect(
      canUseOmxDirectWriteBridge({
        OMX_OMC_INTEROP_ENABLED: '1',
        OMX_OMC_INTEROP_MODE: 'active',
        OMC_INTEROP_TOOLS_ENABLED: '1',
      } as NodeJS.ProcessEnv),
    ).toBe(true);

    expect(
      canUseOmxDirectWriteBridge({
        OMX_OMC_INTEROP_ENABLED: '1',
        OMX_OMC_INTEROP_MODE: 'observe',
        OMC_INTEROP_TOOLS_ENABLED: '1',
      } as NodeJS.ProcessEnv),
    ).toBe(false);

    expect(
      canUseOmxDirectWriteBridge({
        OMX_OMC_INTEROP_ENABLED: '0',
        OMX_OMC_INTEROP_MODE: 'active',
        OMC_INTEROP_TOOLS_ENABLED: '1',
      } as NodeJS.ProcessEnv),
    ).toBe(false);
  });

  it('interop_send_omx_message rejects when direct write path is disabled', async () => {
    const savedEnabled = process.env.OMX_OMC_INTEROP_ENABLED;
    const savedMode = process.env.OMX_OMC_INTEROP_MODE;
    const savedTools = process.env.OMC_INTEROP_TOOLS_ENABLED;

    process.env.OMX_OMC_INTEROP_ENABLED = '0';
    process.env.OMX_OMC_INTEROP_MODE = 'off';
    process.env.OMC_INTEROP_TOOLS_ENABLED = '0';

    try {
      const response = await interopSendOmxMessageTool.handler({
        teamName: 'alpha-team',
        fromWorker: 'omc-bridge',
        toWorker: 'worker-1',
        body: 'blocked',
      });

      expect(response.isError).toBe(true);
      const text = response.content[0]?.text ?? '';
      expect(text.toLowerCase()).toContain('disabled');
    } finally {
      if (savedEnabled === undefined)
        delete process.env.OMX_OMC_INTEROP_ENABLED;
      else process.env.OMX_OMC_INTEROP_ENABLED = savedEnabled;

      if (savedMode === undefined) delete process.env.OMX_OMC_INTEROP_MODE;
      else process.env.OMX_OMC_INTEROP_MODE = savedMode;

      if (savedTools === undefined)
        delete process.env.OMC_INTEROP_TOOLS_ENABLED;
      else process.env.OMC_INTEROP_TOOLS_ENABLED = savedTools;
    }
  });
});

describe('interop_send_omx_message via omx team api CLI', () => {
  const savedEnv: Record<string, string | undefined> = {};
  const envKeys = [
    'OMX_OMC_INTEROP_ENABLED',
    'OMX_OMC_INTEROP_MODE',
    'OMC_INTEROP_TOOLS_ENABLED',
  ] as const;

  beforeEach(() => {
    for (const key of envKeys) savedEnv[key] = process.env[key];
    process.env.OMX_OMC_INTEROP_ENABLED = '1';
    process.env.OMX_OMC_INTEROP_MODE = 'active';
    process.env.OMC_INTEROP_TOOLS_ENABLED = '1';
    execFileMock.mockReset();
  });

  afterEach(() => {
    for (const key of envKeys) {
      if (savedEnv[key] === undefined) delete process.env[key];
      else process.env[key] = savedEnv[key];
    }
  });

  it('send-message happy path parses the ok envelope', async () => {
    mockOmxCliResult({
      stdout: JSON.stringify({
        schema_version: '1.0',
        timestamp: '2026-07-22T00:00:00.000Z',
        command: 'omx team api send-message',
        ok: true,
        operation: 'send-message',
        data: {
          message: {
            message_id: 'msg-42',
            from_worker: 'omc-bridge',
            to_worker: 'worker-1',
            body: 'hello',
            created_at: '2026-07-22T00:00:00.000Z',
          },
          dispatch: { ok: true },
        },
      }),
    });

    const response = await interopSendOmxMessageTool.handler({
      teamName: 'alpha-team',
      fromWorker: 'omc-bridge',
      toWorker: 'worker-1',
      body: 'hello',
    });

    expect(response.isError).toBeUndefined();
    const text = response.content[0]?.text ?? '';
    expect(text).toContain('Message Sent to OMX Worker');
    expect(text).toContain('msg-42');
    expect(text).toContain('worker-1');

    expect(execFileMock).toHaveBeenCalledTimes(1);
    const [cmd, args] = execFileMock.mock.calls[0];
    expect(cmd).toBe('omx');
    expect(args.slice(0, 3)).toEqual(['team', 'api', 'send-message']);
    expect(args[3]).toBe('--input');
    expect(JSON.parse(args[4])).toEqual({
      team_name: 'alpha-team',
      from_worker: 'omc-bridge',
      to_worker: 'worker-1',
      body: 'hello',
    });
    expect(args[5]).toBe('--json');
  });

  it('broadcast happy path parses the ok envelope', async () => {
    mockOmxCliResult({
      stdout: JSON.stringify({
        schema_version: '1.0',
        timestamp: '2026-07-22T00:00:00.000Z',
        command: 'omx team api broadcast',
        ok: true,
        operation: 'broadcast',
        data: {
          count: 2,
          messages: [{ message_id: 'msg-1' }, { message_id: 'msg-2' }],
        },
      }),
    });

    const response = await interopSendOmxMessageTool.handler({
      teamName: 'alpha-team',
      fromWorker: 'omc-bridge',
      toWorker: 'ignored',
      body: 'all hands',
      broadcast: true,
    });

    expect(response.isError).toBeUndefined();
    const text = response.content[0]?.text ?? '';
    expect(text).toContain('Broadcast Sent to OMX Team: alpha-team');
    expect(text).toContain('**Recipients:** 2');
    expect(text).toContain('msg-1, msg-2');

    const [cmd, args] = execFileMock.mock.calls[0];
    expect(cmd).toBe('omx');
    expect(args.slice(0, 3)).toEqual(['team', 'api', 'broadcast']);
    expect(JSON.parse(args[4])).toEqual({
      team_name: 'alpha-team',
      from_worker: 'omc-bridge',
      body: 'all hands',
    });
  });

  it('reports a clear error when the omx binary is missing', async () => {
    const enoent: ExecFileError = Object.assign(new Error('spawn omx ENOENT'), {
      code: 'ENOENT',
    });
    mockOmxCliResult({ error: enoent });

    const response = await interopSendOmxMessageTool.handler({
      teamName: 'alpha-team',
      fromWorker: 'omc-bridge',
      toWorker: 'worker-1',
      body: 'hello',
    });

    expect(response.isError).toBe(true);
    const text = response.content[0]?.text ?? '';
    expect(text).toContain('oh-my-codex must be installed');
  });

  it('surfaces the envelope error message on ok:false', async () => {
    // omx exits non-zero on ok:false envelopes but still prints the JSON
    // envelope on stdout; the bridge must prefer the envelope over the
    // process error.
    mockOmxCliResult({
      error: Object.assign(new Error('Command failed: omx'), { code: 1 }),
      stdout: JSON.stringify({
        schema_version: '1.0',
        timestamp: '2026-07-22T00:00:00.000Z',
        command: 'omx team api send-message',
        ok: false,
        operation: 'send-message',
        error: {
          code: 'team_not_found',
          message: 'Team alpha-team not found',
        },
      }),
    });

    const response = await interopSendOmxMessageTool.handler({
      teamName: 'alpha-team',
      fromWorker: 'omc-bridge',
      toWorker: 'worker-1',
      body: 'hello',
    });

    expect(response.isError).toBe(true);
    const text = response.content[0]?.text ?? '';
    expect(text).toContain('team_not_found');
    expect(text).toContain('Team alpha-team not found');
  });
});

describe('interop mcp bridge artifact surfacing', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'mcp-bridge-artifacts-'));
    // resolveWorkingDirectory now pins via validateWorkingDirectory, which
    // anchors to the trusted worktree root (process.cwd()). Point cwd at the
    // temp dir so the supplied workingDirectory validates to itself.
    vi.spyOn(process, 'cwd').mockReturnValue(tempDir);
    initInteropSession('session-1', tempDir);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('reports artifact-backed task descriptions and results', async () => {
    const description = 'describe ' + 'x'.repeat(5000);
    const sendResponse = await interopSendTaskTool.handler({
      target: 'omx',
      type: 'implement',
      description,
      workingDirectory: tempDir,
    });

    const sendText = sendResponse.content[0]?.text ?? '';
    expect(sendText).toContain('Description artifact:');

    const [task] = readSharedTasks(tempDir);
    expect(task.descriptionArtifact?.path).toBeTruthy();

    updateSharedTask(tempDir, task.id, {
      status: 'completed',
      result: 'result ' + 'y'.repeat(5000),
    });

    const readResponse = await interopReadResultsTool.handler({
      status: 'completed',
      workingDirectory: tempDir,
    });

    const readText = readResponse.content[0]?.text ?? '';
    expect(readText).toContain('Description artifact:');
    expect(readText).toContain('Result artifact:');
    expect(readText).toContain(
      '.omc/state/interop/artifacts/task-description/',
    );
    expect(readText).toContain('.omc/state/interop/artifacts/task-result/');
  });

  it('reports artifact-backed shared messages', async () => {
    const sendResponse = await interopSendMessageTool.handler({
      target: 'omx',
      content: 'message ' + 'z'.repeat(5000),
      workingDirectory: tempDir,
    });

    const sendText = sendResponse.content[0]?.text ?? '';
    expect(sendText).toContain('Content artifact:');

    const [message] = readSharedMessages(tempDir);
    expect(message.contentArtifact?.path).toBeTruthy();

    const readResponse = await interopReadMessagesTool.handler({
      workingDirectory: tempDir,
    });

    const readText = readResponse.content[0]?.text ?? '';
    expect(readText).toContain('Content artifact:');
    expect(readText).toContain('.omc/state/interop/artifacts/message-content/');
  });
});
