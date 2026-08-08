export function resolveHookContextPercent(data: unknown): number | null;

export function resolveHudCacheContextPercent(
  data: unknown,
  directory?: string,
): Promise<number | null>;

export function resolveTranscriptContextPercent(
  transcriptPath?: string,
  tailBytes?: number,
): number | null;

export function resolveContextPercent(
  data: unknown,
  transcriptPath?: string,
  directory?: string,
): Promise<number | null>;
