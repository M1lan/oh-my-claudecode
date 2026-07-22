/**
 * MCP Bridge for Cross-Tool Interoperability
 *
 * Provides MCP tool definitions for communication between OMC and OMX.
 * Tools allow sending tasks and messages between the two systems.
 */

import { z } from 'zod';
import { execFile } from 'child_process';
import { ToolDefinition } from '../tools/types.js';
import type { ArtifactDescriptor } from '../shared/artifact-descriptor.js';
import {
  addSharedTask,
  readSharedTasks,
  addSharedMessage,
  readSharedMessages,
  markMessageAsRead,
  SharedTask,
} from './shared-state.js';
import {
  listOmxTeams,
  readOmxTeamConfig,
  listOmxMailboxMessages,
  listOmxTasks,
} from './omx-team-state.js';
import { validateWorkingDirectory } from '../lib/worktree-paths.js';

export type InteropMode = 'off' | 'observe' | 'active';

export function getInteropMode(
  env: NodeJS.ProcessEnv = process.env,
): InteropMode {
  const raw = (env.OMX_OMC_INTEROP_MODE || 'off').toLowerCase();
  if (raw === 'observe' || raw === 'active') {
    return raw;
  }
  return 'off';
}

export function canUseOmxDirectWriteBridge(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const interopEnabled = env.OMX_OMC_INTEROP_ENABLED === '1';
  const toolsEnabled = env.OMC_INTEROP_TOOLS_ENABLED === '1';
  const mode = getInteropMode(env);
  return interopEnabled && toolsEnabled && mode === 'active';
}

function resolveWorkingDirectory(workingDirectory?: string): string {
  // Pin an agent-supplied workingDirectory to the trusted worktree root so a
  // crafted absolute/traversal path cannot make interop state read or write
  // outside the current repo. Matches the rest of the MCP tool surface
  // (state-tools, notepad-tools, trace-tools).
  return validateWorkingDirectory(workingDirectory);
}

function getInteropSource(target: 'omc' | 'omx'): 'omc' | 'omx' {
  return target === 'omc' ? 'omx' : 'omc';
}

function formatToolError(action: string, error: unknown) {
  return {
    content: [
      {
        type: 'text' as const,
        text: `Error ${action}: ${error instanceof Error ? error.message : String(error)}`,
      },
    ],
    isError: true,
  };
}

function truncatePreview(text: string, maxChars: number): string {
  return text.length > maxChars ? `${text.slice(0, maxChars)}...` : text;
}

// ============================================================================
// omx team api CLI bridge (OMX mutation contract)
// ============================================================================

// Per the OMX interop mutation contract (oh-my-codex
// docs/interop-team-mutation-contract.md), direct writes to
// .omx/state/team/... are unsupported; `omx team api <operation> --input
// <json> --json` is the rule of record for mutations. Reads stay direct.

const OMX_CLI_TIMEOUT_MS = 30_000;

interface OmxTeamApiEnvelope {
  ok?: boolean;
  operation?: string;
  data?: Record<string, unknown>;
  error?: { code?: string; message?: string };
}

function runOmxTeamApi(
  operation: 'send-message' | 'broadcast',
  input: Record<string, unknown>,
  cwd: string,
): Promise<OmxTeamApiEnvelope> {
  return new Promise((resolvePromise, rejectPromise) => {
    execFile(
      'omx',
      ['team', 'api', operation, '--input', JSON.stringify(input), '--json'],
      { cwd, timeout: OMX_CLI_TIMEOUT_MS },
      (error, stdout, stderr) => {
        if (error && (error as NodeJS.ErrnoException).code === 'ENOENT') {
          rejectPromise(
            new Error(
              'omx CLI not found. oh-my-codex must be installed for direct OMX messaging (`omx team api` is the only supported mutation path).',
            ),
          );
          return;
        }

        // `omx team api ... --json` prints the envelope on stdout even for
        // ok:false results (which exit non-zero), so parse stdout before
        // treating a process error as fatal.
        const raw = typeof stdout === 'string' ? stdout.trim() : '';
        if (raw) {
          try {
            resolvePromise(JSON.parse(raw) as OmxTeamApiEnvelope);
            return;
          } catch {
            // Not a JSON envelope; fall through to error handling.
          }
        }

        if (error) {
          const stderrText = typeof stderr === 'string' ? stderr.trim() : '';
          rejectPromise(
            new Error(
              `omx team api ${operation} failed: ${error.message}${stderrText ? `\n${stderrText}` : ''}`,
            ),
          );
          return;
        }

        rejectPromise(
          new Error(
            `omx team api ${operation} returned no parseable JSON envelope`,
          ),
        );
      },
    );
  });
}

function formatOmxEnvelopeError(
  operation: 'send-message' | 'broadcast',
  envelope: OmxTeamApiEnvelope,
) {
  const code = envelope.error?.code ? ` (${envelope.error.code})` : '';
  const message = envelope.error?.message ?? 'unknown error';
  return {
    content: [
      {
        type: 'text' as const,
        text: `omx team api ${operation} failed${code}: ${message}`,
      },
    ],
    isError: true,
  };
}

function formatArtifactDescriptorLines(
  label: string,
  descriptor?: ArtifactDescriptor,
): string[] {
  if (!descriptor) return [];

  const lines = [`- **${label} artifact:** \`${descriptor.path}\``];
  if (descriptor.sizeBytes !== undefined) {
    lines.push(`- **${label} size:** ${descriptor.sizeBytes} bytes`);
  }
  if (descriptor.contentHash) {
    lines.push(
      `- **${label} hash:** \`${descriptor.contentHash.slice(0, 16)}…\``,
    );
  }

  return lines;
}

// ============================================================================
// interop_send_task - Send a task to the other tool
// ============================================================================

export const interopSendTaskTool: ToolDefinition<{
  target: z.ZodEnum<['omc', 'omx']>;
  type: z.ZodEnum<['analyze', 'implement', 'review', 'test', 'custom']>;
  description: z.ZodString;
  context: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodUnknown>>;
  files: z.ZodOptional<z.ZodArray<z.ZodString>>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_send_task',
  description:
    'Send a task to the other tool (OMC -> OMX or OMX -> OMC) for execution. The task is written to shared interop state (.omc/state/interop); the target tool must read it explicitly — delivery is not automatic.',
  schema: {
    target: z.enum(['omc', 'omx']).describe('Target tool to send the task to'),
    type: z
      .enum(['analyze', 'implement', 'review', 'test', 'custom'])
      .describe('Type of task'),
    description: z.string().describe('Task description'),
    context: z
      .record(z.string(), z.unknown())
      .optional()
      .describe('Additional context data'),
    files: z
      .array(z.string())
      .optional()
      .describe('List of relevant file paths'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    const { target, type, description, context, files, workingDirectory } =
      args;

    try {
      const cwd = resolveWorkingDirectory(workingDirectory);
      const source = getInteropSource(target);

      const task = addSharedTask(cwd, {
        source,
        target,
        type,
        description,
        context,
        files,
      });

      return {
        content: [
          {
            type: 'text' as const,
            text:
              `## Task Sent to ${target.toUpperCase()}\n\n` +
              `**Task ID:** ${task.id}\n` +
              `**Type:** ${task.type}\n` +
              `**Description:** ${task.description}\n` +
              (task.descriptionArtifact
                ? `**Description artifact:** ${task.descriptionArtifact.path}\n`
                : '') +
              `**Status:** ${task.status}\n` +
              `**Created:** ${task.createdAt}\n\n` +
              (task.files ? `**Files:** ${task.files.join(', ')}\n\n` : '') +
              `Task written to shared interop state (.omc/state/interop). ` +
              `${target.toUpperCase()} must read it explicitly (via its interop tools ` +
              `or the shared state directory) — delivery is not automatic.`,
          },
        ],
      };
    } catch (error) {
      return formatToolError('sending task', error);
    }
  },
};

// ============================================================================
// interop_read_results - Read task results from the other tool
// ============================================================================

export const interopReadResultsTool: ToolDefinition<{
  source: z.ZodOptional<z.ZodEnum<['omc', 'omx']>>;
  status: z.ZodOptional<
    z.ZodEnum<['pending', 'in_progress', 'completed', 'failed']>
  >;
  limit: z.ZodOptional<z.ZodNumber>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_read_results',
  description:
    'Read task results from the shared interop state. Can filter by source tool and status.',
  schema: {
    source: z.enum(['omc', 'omx']).optional().describe('Filter by source tool'),
    status: z
      .enum(['pending', 'in_progress', 'completed', 'failed'])
      .optional()
      .describe('Filter by task status'),
    limit: z
      .number()
      .optional()
      .describe('Maximum number of tasks to return (default: 10)'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    const { source, status, limit = 10, workingDirectory } = args;

    try {
      const cwd = resolveWorkingDirectory(workingDirectory);

      const tasks = readSharedTasks(cwd, {
        source: source as 'omc' | 'omx' | undefined,
        status: status as SharedTask['status'] | undefined,
      });

      const limitedTasks = tasks.slice(0, limit);

      if (limitedTasks.length === 0) {
        return {
          content: [
            {
              type: 'text' as const,
              text: '## No Tasks Found\n\nNo tasks match the specified filters.',
            },
          ],
        };
      }

      const lines: string[] = [
        `## Tasks (${limitedTasks.length}${tasks.length > limit ? ` of ${tasks.length}` : ''})\n`,
      ];

      for (const task of limitedTasks) {
        const statusIcon =
          task.status === 'completed'
            ? '✓'
            : task.status === 'failed'
              ? '✗'
              : task.status === 'in_progress'
                ? '⋯'
                : '○';

        lines.push(`### ${statusIcon} ${task.id}`);
        lines.push(`- **Type:** ${task.type}`);
        lines.push(
          `- **Source:** ${task.source.toUpperCase()} → **Target:** ${task.target.toUpperCase()}`,
        );
        lines.push(`- **Status:** ${task.status}`);
        lines.push(`- **Description:** ${task.description}`);
        lines.push(`- **Created:** ${task.createdAt}`);
        lines.push(
          ...formatArtifactDescriptorLines(
            'Description',
            task.descriptionArtifact,
          ),
        );

        if (task.files && task.files.length > 0) {
          lines.push(`- **Files:** ${task.files.join(', ')}`);
        }

        if (task.result) {
          lines.push(`- **Result:** ${truncatePreview(task.result, 200)}`);
        }
        lines.push(
          ...formatArtifactDescriptorLines('Result', task.resultArtifact),
        );

        if (task.error) {
          lines.push(`- **Error:** ${task.error}`);
        }

        if (task.completedAt) {
          lines.push(`- **Completed:** ${task.completedAt}`);
        }

        lines.push('');
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: lines.join('\n'),
          },
        ],
      };
    } catch (error) {
      return formatToolError('reading tasks', error);
    }
  },
};

// ============================================================================
// interop_send_message - Send a message to the other tool
// ============================================================================

export const interopSendMessageTool: ToolDefinition<{
  target: z.ZodEnum<['omc', 'omx']>;
  content: z.ZodString;
  metadata: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodUnknown>>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_send_message',
  description:
    'Send a message to the other tool for informational purposes or coordination.',
  schema: {
    target: z
      .enum(['omc', 'omx'])
      .describe('Target tool to send the message to'),
    content: z.string().describe('Message content'),
    metadata: z
      .record(z.string(), z.unknown())
      .optional()
      .describe('Additional metadata'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    const { target, content, metadata, workingDirectory } = args;

    try {
      const cwd = resolveWorkingDirectory(workingDirectory);
      const source = getInteropSource(target);

      const message = addSharedMessage(cwd, {
        source,
        target,
        content,
        metadata,
      });

      return {
        content: [
          {
            type: 'text' as const,
            text:
              `## Message Sent to ${target.toUpperCase()}\n\n` +
              `**Message ID:** ${message.id}\n` +
              `**Content:** ${message.content}\n` +
              (message.contentArtifact
                ? `**Content artifact:** ${message.contentArtifact.path}\n`
                : '') +
              `**Timestamp:** ${message.timestamp}\n\n` +
              `Message written to shared interop state (.omc/state/interop). ` +
              `${target.toUpperCase()} must read it explicitly — delivery is not automatic.`,
          },
        ],
      };
    } catch (error) {
      return formatToolError('sending message', error);
    }
  },
};

// ============================================================================
// interop_read_messages - Read messages from the other tool
// ============================================================================

export const interopReadMessagesTool: ToolDefinition<{
  source: z.ZodOptional<z.ZodEnum<['omc', 'omx']>>;
  unreadOnly: z.ZodOptional<z.ZodBoolean>;
  limit: z.ZodOptional<z.ZodNumber>;
  markAsRead: z.ZodOptional<z.ZodBoolean>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_read_messages',
  description:
    'Read messages from the shared interop state. Can filter by source tool and read status.',
  schema: {
    source: z.enum(['omc', 'omx']).optional().describe('Filter by source tool'),
    unreadOnly: z
      .boolean()
      .optional()
      .describe('Show only unread messages (default: false)'),
    limit: z
      .number()
      .optional()
      .describe('Maximum number of messages to return (default: 10)'),
    markAsRead: z
      .boolean()
      .optional()
      .describe('Mark retrieved messages as read (default: false)'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    const {
      source,
      unreadOnly = false,
      limit = 10,
      markAsRead = false,
      workingDirectory,
    } = args;

    try {
      const cwd = resolveWorkingDirectory(workingDirectory);

      const messages = readSharedMessages(cwd, {
        source: source as 'omc' | 'omx' | undefined,
        unreadOnly,
      });

      const limitedMessages = messages.slice(0, limit);

      if (limitedMessages.length === 0) {
        return {
          content: [
            {
              type: 'text' as const,
              text: '## No Messages Found\n\nNo messages match the specified filters.',
            },
          ],
        };
      }

      // Mark messages as read if requested
      if (markAsRead) {
        for (const message of limitedMessages) {
          markMessageAsRead(cwd, message.id);
        }
      }

      const lines: string[] = [
        `## Messages (${limitedMessages.length}${messages.length > limit ? ` of ${messages.length}` : ''})\n`,
      ];

      for (const message of limitedMessages) {
        const readIcon = message.read ? '✓' : '○';

        lines.push(`### ${readIcon} ${message.id}`);
        lines.push(
          `- **From:** ${message.source.toUpperCase()} → **To:** ${message.target.toUpperCase()}`,
        );
        lines.push(`- **Content:** ${message.content}`);
        lines.push(`- **Timestamp:** ${message.timestamp}`);
        lines.push(`- **Read:** ${message.read ? 'Yes' : 'No'}`);
        lines.push(
          ...formatArtifactDescriptorLines('Content', message.contentArtifact),
        );

        if (message.metadata) {
          lines.push(`- **Metadata:** ${JSON.stringify(message.metadata)}`);
        }

        lines.push('');
      }

      if (markAsRead) {
        lines.push(`\n*${limitedMessages.length} message(s) marked as read*`);
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: lines.join('\n'),
          },
        ],
      };
    } catch (error) {
      return formatToolError('reading messages', error);
    }
  },
};

// ============================================================================
// interop_list_omx_teams - List active omx teams
// ============================================================================

export const interopListOmxTeamsTool: ToolDefinition<{
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_list_omx_teams',
  description:
    'List active OMX (oh-my-codex) teams from .omx/state/team/. Shows team names and basic configuration.',
  schema: {
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    try {
      const cwd = resolveWorkingDirectory(args.workingDirectory);
      const teamNames = await listOmxTeams(cwd);

      if (teamNames.length === 0) {
        return {
          content: [
            {
              type: 'text' as const,
              text: '## No OMX Teams Found\n\nNo active OMX teams detected in .omx/state/team/.',
            },
          ],
        };
      }

      const lines: string[] = [`## OMX Teams (${teamNames.length})\n`];

      for (const name of teamNames) {
        const config = await readOmxTeamConfig(name, cwd);
        if (config) {
          lines.push(`### ${name}`);
          lines.push(`- **Task:** ${config.task}`);
          lines.push(
            `- **Workers:** ${config.worker_count} (${config.agent_type})`,
          );
          lines.push(`- **Created:** ${config.created_at}`);
          lines.push(
            `- **Workers:** ${config.workers.map((w) => w.name).join(', ')}`,
          );
          lines.push('');
        } else {
          lines.push(`### ${name} (config not readable)\n`);
        }
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: lines.join('\n'),
          },
        ],
      };
    } catch (error) {
      return formatToolError('listing OMX teams', error);
    }
  },
};

// ============================================================================
// interop_send_omx_message - Send message to omx team mailbox
// ============================================================================

export const interopSendOmxMessageTool: ToolDefinition<{
  teamName: z.ZodString;
  fromWorker: z.ZodString;
  toWorker: z.ZodString;
  body: z.ZodString;
  broadcast: z.ZodOptional<z.ZodBoolean>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_send_omx_message',
  description:
    'Send a message to an OMX team worker mailbox using the native omx format. Supports direct messages and broadcasts.',
  schema: {
    teamName: z.string().describe('OMX team name'),
    fromWorker: z.string().describe('Sender worker name (e.g., "omc-bridge")'),
    toWorker: z
      .string()
      .describe('Target worker name (ignored if broadcast=true)'),
    body: z.string().describe('Message body'),
    broadcast: z
      .boolean()
      .optional()
      .describe('Broadcast to all workers (default: false)'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    try {
      if (!canUseOmxDirectWriteBridge()) {
        return {
          content: [
            {
              type: 'text' as const,
              text: 'Direct OMX mailbox writes are disabled. Use broker-mediated team_* MCP path or enable active interop flags explicitly.',
            },
          ],
          isError: true,
        };
      }

      const cwd = resolveWorkingDirectory(args.workingDirectory);

      if (args.broadcast) {
        const envelope = await runOmxTeamApi(
          'broadcast',
          {
            team_name: args.teamName,
            from_worker: args.fromWorker,
            body: args.body,
          },
          cwd,
        );
        if (!envelope.ok) {
          return formatOmxEnvelopeError('broadcast', envelope);
        }
        const data = envelope.data ?? {};
        const messages = Array.isArray(data.messages)
          ? (data.messages as Array<{ message_id?: string }>)
          : [];
        const count =
          typeof data.count === 'number' ? data.count : messages.length;
        return {
          content: [
            {
              type: 'text' as const,
              text:
                `## Broadcast Sent to OMX Team: ${args.teamName}\n\n` +
                `**From:** ${args.fromWorker}\n` +
                `**Recipients:** ${count}\n` +
                `**Message IDs:** ${messages.map((m) => m.message_id).join(', ')}\n\n` +
                `Message delivered to ${count} worker mailbox(es) via omx team api.`,
            },
          ],
        };
      }

      const envelope = await runOmxTeamApi(
        'send-message',
        {
          team_name: args.teamName,
          from_worker: args.fromWorker,
          to_worker: args.toWorker,
          body: args.body,
        },
        cwd,
      );
      if (!envelope.ok) {
        return formatOmxEnvelopeError('send-message', envelope);
      }
      const msg = (envelope.data?.message ?? {}) as {
        message_id?: string;
        from_worker?: string;
        to_worker?: string;
        created_at?: string;
      };
      const toWorker = msg.to_worker ?? args.toWorker;
      return {
        content: [
          {
            type: 'text' as const,
            text:
              `## Message Sent to OMX Worker\n\n` +
              `**Team:** ${args.teamName}\n` +
              `**From:** ${msg.from_worker ?? args.fromWorker}\n` +
              `**To:** ${toWorker}\n` +
              `**Message ID:** ${msg.message_id ?? 'unknown'}\n` +
              `**Created:** ${msg.created_at ?? 'unknown'}\n\n` +
              `Message delivered to ${toWorker}'s mailbox via omx team api.`,
          },
        ],
      };
    } catch (error) {
      return formatToolError('sending OMX message', error);
    }
  },
};

// ============================================================================
// interop_read_omx_messages - Read messages from omx team mailbox
// ============================================================================

export const interopReadOmxMessagesTool: ToolDefinition<{
  teamName: z.ZodString;
  workerName: z.ZodString;
  limit: z.ZodOptional<z.ZodNumber>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_read_omx_messages',
  description: 'Read messages from an OMX team worker mailbox.',
  schema: {
    teamName: z.string().describe('OMX team name'),
    workerName: z.string().describe('Worker name whose mailbox to read'),
    limit: z
      .number()
      .optional()
      .describe('Maximum number of messages to return (default: 20)'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    try {
      const cwd = resolveWorkingDirectory(args.workingDirectory);
      const limit = args.limit ?? 20;
      const messages = await listOmxMailboxMessages(
        args.teamName,
        args.workerName,
        cwd,
      );

      if (messages.length === 0) {
        return {
          content: [
            {
              type: 'text' as const,
              text: `## No Messages\n\nNo messages in ${args.workerName}'s mailbox for team ${args.teamName}.`,
            },
          ],
        };
      }

      const limited = messages.slice(-limit); // most recent N messages
      const lines: string[] = [
        `## OMX Mailbox: ${args.workerName} @ ${args.teamName} (${limited.length}${messages.length > limit ? ` of ${messages.length}` : ''})\n`,
      ];

      for (const msg of limited) {
        const deliveredIcon = msg.delivered_at ? '✓' : '○';
        lines.push(`### ${deliveredIcon} ${msg.message_id}`);
        lines.push(`- **From:** ${msg.from_worker}`);
        lines.push(`- **To:** ${msg.to_worker}`);
        lines.push(`- **Body:** ${truncatePreview(msg.body, 300)}`);
        lines.push(`- **Created:** ${msg.created_at}`);
        if (msg.delivered_at)
          lines.push(`- **Delivered:** ${msg.delivered_at}`);
        lines.push('');
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: lines.join('\n'),
          },
        ],
      };
    } catch (error) {
      return formatToolError('reading OMX messages', error);
    }
  },
};

// ============================================================================
// interop_read_omx_tasks - Read omx team tasks
// ============================================================================

export const interopReadOmxTasksTool: ToolDefinition<{
  teamName: z.ZodString;
  status: z.ZodOptional<
    z.ZodEnum<['pending', 'blocked', 'in_progress', 'completed', 'failed']>
  >;
  limit: z.ZodOptional<z.ZodNumber>;
  workingDirectory: z.ZodOptional<z.ZodString>;
}> = {
  name: 'interop_read_omx_tasks',
  description: 'Read tasks from an OMX team. Can filter by status.',
  schema: {
    teamName: z.string().describe('OMX team name'),
    status: z
      .enum(['pending', 'blocked', 'in_progress', 'completed', 'failed'])
      .optional()
      .describe('Filter by task status'),
    limit: z
      .number()
      .optional()
      .describe('Maximum number of tasks to return (default: 20)'),
    workingDirectory: z
      .string()
      .optional()
      .describe('Working directory (defaults to cwd)'),
  },
  handler: async (args) => {
    try {
      const cwd = resolveWorkingDirectory(args.workingDirectory);
      const limit = args.limit ?? 20;
      let tasks = await listOmxTasks(args.teamName, cwd);

      if (args.status) {
        tasks = tasks.filter((t) => t.status === args.status);
      }

      if (tasks.length === 0) {
        return {
          content: [
            {
              type: 'text' as const,
              text: `## No Tasks\n\nNo tasks found for OMX team ${args.teamName}${args.status ? ` with status "${args.status}"` : ''}.`,
            },
          ],
        };
      }

      const limited = tasks.slice(0, limit);
      const lines: string[] = [
        `## OMX Tasks: ${args.teamName} (${limited.length}${tasks.length > limit ? ` of ${tasks.length}` : ''})\n`,
      ];

      for (const task of limited) {
        const statusIcon =
          task.status === 'completed'
            ? '✓'
            : task.status === 'failed'
              ? '✗'
              : task.status === 'in_progress'
                ? '⋯'
                : task.status === 'blocked'
                  ? '⊘'
                  : '○';

        lines.push(`### ${statusIcon} Task ${task.id}: ${task.subject}`);
        lines.push(`- **Status:** ${task.status}`);
        if (task.owner) lines.push(`- **Owner:** ${task.owner}`);
        lines.push(
          `- **Description:** ${truncatePreview(task.description, 200)}`,
        );
        lines.push(`- **Created:** ${task.created_at}`);
        if (task.result)
          lines.push(`- **Result:** ${truncatePreview(task.result, 200)}`);
        if (task.error) lines.push(`- **Error:** ${task.error}`);
        if (task.completed_at)
          lines.push(`- **Completed:** ${task.completed_at}`);
        lines.push('');
      }

      return {
        content: [
          {
            type: 'text' as const,
            text: lines.join('\n'),
          },
        ],
      };
    } catch (error) {
      return formatToolError('reading OMX tasks', error);
    }
  },
};

/**
 * Get all interop MCP tools for registration
 */
export function getInteropTools(): ToolDefinition<any>[] {
  return [
    interopSendTaskTool,
    interopReadResultsTool,
    interopSendMessageTool,
    interopReadMessagesTool,
    interopListOmxTeamsTool,
    interopSendOmxMessageTool,
    interopReadOmxMessagesTool,
    interopReadOmxTasksTool,
  ];
}
