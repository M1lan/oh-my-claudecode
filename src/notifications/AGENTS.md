<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# notifications

## Purpose
Multi-platform notification system for session lifecycle events. Dispatches notifications to Discord (webhook and bot API), Telegram, Slack, and generic webhooks when sessions start, stop, end, go idle, or ask the user a question. All sends are non-blocking with timeouts and swallow failures to avoid blocking hooks. Includes message formatting with markdown support and tmux-based local notifications.

## Key Files
| File | Description |
|------|-------------|
| `types.ts` | All notification interfaces: `NotificationEvent`, `NotificationPlatform`, `DiscordNotificationConfig`, `TelegramNotificationConfig`, `SlackNotificationConfig`, `WebhookNotificationConfig`, `NotificationPayload`, `DispatchResult` |
| `dispatcher.ts` | `dispatchNotification()` — fans out a `NotificationPayload` to all configured platforms concurrently with per-platform and overall timeouts |
| `formatter.ts` | `formatNotification()` — produces human-readable markdown or plain-text message strings for each `NotificationEvent` type |
| `config.ts` | Reads and validates notification configuration from user settings; `parseMentionAllowedMentions()` for Discord mention parsing |
| `tmux.ts` | Sends notifications via tmux `display-message` for local terminal visibility |
| `index.ts` | Barrel export of public API |

## For AI Agents

### Working In This Directory
- `SEND_TIMEOUT_MS` (10s) and `DISPATCH_TIMEOUT_MS` (15s) are module constants in `dispatcher.ts`. Do not remove these — unresponsive webhook endpoints must not block hook execution.
- Discord has a 2000-character content limit enforced by `composeDiscordContent()`. Truncation happens in the message body, not the mention prefix.
- Adding a new platform requires: a new config interface in `types.ts`, a new send function in `dispatcher.ts`, a new format branch in `formatter.ts`, and a new config reader in `config.ts`.
- `NotificationEvent` values are the stable string identifiers written to config files. Do not rename existing values.
- The `tmux.ts` module is a local-only channel and does not require network access.

### Common Patterns
- All platform send functions return `NotificationResult` with `{ success: boolean, platform, error? }`.
- `dispatchNotification(payload, config)` returns `DispatchResult[]` — one per configured platform. Callers should not await the overall result if they want fire-and-forget.
- Message formatting uses markdown for Discord/Telegram, plain text for Slack/webhook.

## Dependencies

### Internal
None — standalone notification module.

### External
- `node:https` — HTTPS requests to Discord/Telegram/Slack/webhook endpoints
- `node:path` — `basename()` for project display name
- `tmux` (system binary, optional) — local terminal notifications

<!-- MANUAL: -->
