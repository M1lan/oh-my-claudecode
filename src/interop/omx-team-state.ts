/**
 * OMX Team State Layer (forked from oh-my-codex)
 *
 * Provides read access to .omx/state/team/{name}/ directories, enabling omc
 * to observe omx teams using the native omx format. Mutations must go through
 * `omx team api <operation> --input <json> --json` per the OMX interop
 * mutation contract (oh-my-codex docs/interop-team-mutation-contract.md);
 * direct writes to .omx/state/team/... are unsupported.
 *
 * Data layout: .omx/state/team/{name}/
 *   config.json              — TeamConfig
 *   manifest.v2.json         — TeamManifestV2
 *   mailbox/{worker}.json    — TeamMailbox
 *   tasks/task-{id}.json     — TeamTask
 *   events/events.ndjson     — TeamEvent (append-only)
 */

import { readFile, readdir } from 'fs/promises';
import { join, resolve, relative, isAbsolute } from 'path';
import { existsSync } from 'fs';
import { z } from 'zod';
import { atomicWriteJson } from '../lib/atomic-write.js';
import { withFileLock } from '../lib/file-lock.js';

// ============================================================================
// Types (matching omx team state format)
// ============================================================================

export interface OmxTeamConfig {
  name: string;
  task: string;
  agent_type: string;
  worker_count: number;
  max_workers: number;
  workers: OmxWorkerInfo[];
  created_at: string;
  tmux_session: string;
  next_task_id: number;
}

export interface OmxWorkerInfo {
  name: string;
  index: number;
  role: string;
  assigned_tasks: string[];
  pid?: number;
  pane_id?: string;
}

export interface OmxTeamTask {
  id: string;
  subject: string;
  description: string;
  status: 'pending' | 'blocked' | 'in_progress' | 'completed' | 'failed';
  requires_code_change?: boolean;
  owner?: string;
  result?: string;
  error?: string;
  blocked_by?: string[];
  depends_on?: string[];
  version?: number;
  created_at: string;
  completed_at?: string;
}

export interface OmxTeamMailboxMessage {
  message_id: string;
  from_worker: string;
  to_worker: string;
  body: string;
  created_at: string;
  notified_at?: string;
  delivered_at?: string;
}

export interface OmxTeamMailbox {
  worker: string;
  messages: OmxTeamMailboxMessage[];
}

export interface OmxTeamManifestV2 {
  schema_version: 2;
  name: string;
  task: string;
  tmux_session: string;
  worker_count: number;
  workers: OmxWorkerInfo[];
  next_task_id: number;
  created_at: string;
  [key: string]: unknown; // allow extra fields (leader, policy, etc.)
}

// ============================================================================
// Zod schemas for runtime validation
// ============================================================================

const OmxWorkerInfoSchema = z.object({
  name: z.string(),
  index: z.number(),
  role: z.string(),
  assigned_tasks: z.array(z.string()),
  pid: z.number().optional(),
  pane_id: z.string().optional(),
});

const OmxTeamManifestV2Schema = z
  .object({
    schema_version: z.literal(2),
    name: z.string(),
    task: z.string(),
    tmux_session: z.string(),
    worker_count: z.number(),
    workers: z.array(OmxWorkerInfoSchema),
    next_task_id: z.number(),
    created_at: z.string(),
  })
  .passthrough();

const OmxTeamConfigSchema = z.object({
  name: z.string(),
  task: z.string(),
  agent_type: z.string(),
  worker_count: z.number(),
  max_workers: z.number(),
  workers: z.array(OmxWorkerInfoSchema),
  created_at: z.string(),
  tmux_session: z.string(),
  next_task_id: z.number(),
});

// ============================================================================
// Path helpers
// ============================================================================

/**
 * Guard against path traversal: assert that `childPath` stays inside
 * `parentDir`. OMX team/worker names originate from another tool's state tree
 * (not OMC-controlled), so we defend the directory boundary rather than
 * restrict the charset — a crafted `../` segment in a team/worker name would
 * otherwise let a read/write escape `.omx/state/team/`.
 */
function assertWithin(parentDir: string, childPath: string): void {
  const parent = resolve(parentDir);
  const child = resolve(childPath);
  const rel = relative(parent, child);
  if (rel === '' || rel.startsWith('..') || isAbsolute(rel)) {
    throw new Error(`Refusing path outside OMX team boundary: ${childPath}`);
  }
}

/** Root of omx state: {cwd}/.omx/state/ */
function omxStateDir(cwd: string): string {
  return join(cwd, '.omx', 'state');
}

/** Team directory: .omx/state/team/{name}/ */
function teamDir(teamName: string, cwd: string): string {
  const root = join(omxStateDir(cwd), 'team');
  const dir = join(root, teamName);
  assertWithin(root, dir);
  return dir;
}

function mailboxPath(
  teamName: string,
  workerName: string,
  cwd: string,
): string {
  const dir = join(teamDir(teamName, cwd), 'mailbox');
  const p = join(dir, `${workerName}.json`);
  assertWithin(dir, p);
  return p;
}

function taskFilePath(teamName: string, taskId: string, cwd: string): string {
  const dir = join(teamDir(teamName, cwd), 'tasks');
  const p = join(dir, `task-${taskId}.json`);
  assertWithin(dir, p);
  return p;
}

// ============================================================================
// Discovery
// ============================================================================

/**
 * List active omx teams by scanning .omx/state/team/ subdirectories
 */
export async function listOmxTeams(cwd: string): Promise<string[]> {
  const teamsRoot = join(omxStateDir(cwd), 'team');
  if (!existsSync(teamsRoot)) return [];

  try {
    const entries = await readdir(teamsRoot, { withFileTypes: true });
    return entries
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    return [];
  }
}

// ============================================================================
// Config
// ============================================================================

/**
 * Read team config (tries manifest.v2.json first, falls back to config.json)
 */
export async function readOmxTeamConfig(
  teamName: string,
  cwd: string,
): Promise<OmxTeamConfig | null> {
  const root = teamDir(teamName, cwd);
  if (!existsSync(root)) return null;

  // Try manifest.v2.json first
  const manifestPath = join(root, 'manifest.v2.json');
  if (existsSync(manifestPath)) {
    try {
      const raw = await readFile(manifestPath, 'utf8');
      const manifestResult = OmxTeamManifestV2Schema.safeParse(JSON.parse(raw));
      if (manifestResult.success) {
        const manifest = manifestResult.data;
        return {
          name: manifest.name,
          task: manifest.task,
          agent_type: manifest.workers?.[0]?.role ?? 'executor',
          worker_count: manifest.worker_count,
          max_workers: 20,
          workers: manifest.workers ?? [],
          created_at: manifest.created_at,
          tmux_session: manifest.tmux_session,
          next_task_id: manifest.next_task_id,
        };
      }
    } catch {
      // Fall through to config.json
    }
  }

  // Fall back to config.json
  const configPath = join(root, 'config.json');
  if (!existsSync(configPath)) return null;

  try {
    const raw = await readFile(configPath, 'utf8');
    const configResult = OmxTeamConfigSchema.safeParse(JSON.parse(raw));
    return configResult.success ? configResult.data : null;
  } catch {
    return null;
  }
}

// ============================================================================
// Mailbox
// ============================================================================

/**
 * Read a worker's mailbox
 */
export async function readOmxMailbox(
  teamName: string,
  workerName: string,
  cwd: string,
): Promise<OmxTeamMailbox> {
  const p = mailboxPath(teamName, workerName, cwd);
  try {
    if (!existsSync(p)) return { worker: workerName, messages: [] };
    const raw = await readFile(p, 'utf8');
    const parsed = JSON.parse(raw) as { worker?: unknown; messages?: unknown };
    if (parsed.worker !== workerName || !Array.isArray(parsed.messages)) {
      return { worker: workerName, messages: [] };
    }
    return {
      worker: workerName,
      messages: parsed.messages as OmxTeamMailboxMessage[],
    };
  } catch {
    return { worker: workerName, messages: [] };
  }
}

/**
 * List all messages in a worker's mailbox
 */
export async function listOmxMailboxMessages(
  teamName: string,
  workerName: string,
  cwd: string,
): Promise<OmxTeamMailboxMessage[]> {
  const mailbox = await readOmxMailbox(teamName, workerName, cwd);
  return mailbox.messages;
}

// Direct mailbox mutations (sendOmxDirectMessage, broadcastOmxMessage,
// appendOmxTeamEvent) were removed: the OMX mutation contract forbids direct
// writes to .omx/state/team/... — interop_send_omx_message now shells out to
// `omx team api send-message|broadcast --input <json> --json` instead.

/**
 * Mark a message as delivered in an omx worker's mailbox
 *
 * @deprecated Interop active write path must go through broker -> OMX team_* MCP APIs.
 */
export async function markOmxMessageDelivered(
  teamName: string,
  workerName: string,
  messageId: string,
  cwd: string,
): Promise<boolean> {
  const p = mailboxPath(teamName, workerName, cwd);
  return await withFileLock(
    p + '.lock',
    async () => {
      const mailbox = await readOmxMailbox(teamName, workerName, cwd);
      const msg = mailbox.messages.find((m) => m.message_id === messageId);
      if (!msg) return false;
      if (!msg.delivered_at) {
        msg.delivered_at = new Date().toISOString();
        await atomicWriteJson(p, mailbox);
      }
      return true;
    },
    { timeoutMs: 5000 },
  );
}

// ============================================================================
// Tasks
// ============================================================================

/**
 * Read a single omx team task
 */
export async function readOmxTask(
  teamName: string,
  taskId: string,
  cwd: string,
): Promise<OmxTeamTask | null> {
  const p = taskFilePath(teamName, taskId, cwd);
  if (!existsSync(p)) return null;
  try {
    const raw = await readFile(p, 'utf8');
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object') return null;
    const t = parsed as Record<string, unknown>;
    if (
      typeof t.id !== 'string' ||
      typeof t.subject !== 'string' ||
      typeof t.status !== 'string'
    )
      return null;
    return parsed as OmxTeamTask;
  } catch {
    return null;
  }
}

/**
 * List all tasks in an omx team
 */
export async function listOmxTasks(
  teamName: string,
  cwd: string,
): Promise<OmxTeamTask[]> {
  const tasksRoot = join(teamDir(teamName, cwd), 'tasks');
  if (!existsSync(tasksRoot)) return [];

  try {
    const files = await readdir(tasksRoot);
    const tasks: OmxTeamTask[] = [];

    for (const f of files) {
      const m = /^task-(\d+)\.json$/.exec(f);
      if (!m) continue;
      const task = await readOmxTask(teamName, m[1], cwd);
      if (task) tasks.push(task);
    }

    tasks.sort((a, b) => Number(a.id) - Number(b.id));
    return tasks;
  } catch {
    return [];
  }
}
