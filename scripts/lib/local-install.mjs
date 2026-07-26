/**
 * Local-source install detection.
 *
 * When OMC runs from a local checkout - a marketplace registered with
 * `source.source === 'directory'`, or a plugin root that is itself a git
 * working tree carrying the repo's own marketplace manifest - the npm registry
 * is not an actionable update channel. The checkout is the source of truth and
 * updates arrive through git, so advertising a registry release would point the
 * user at an install path that overwrites their local build.
 */

import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { isAbsolute, join, relative, resolve } from 'node:path';
import { getClaudeConfigDir } from './config-dir.mjs';

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf-8'));
  } catch {
    return null;
  }
}

function canonicalPath(path) {
  const absolute = resolve(path);
  try {
    return realpathSync(absolute);
  } catch {
    return absolute;
  }
}

function isInsideOrEqual(parent, child) {
  const rel = relative(canonicalPath(parent), canonicalPath(child));
  return rel === '' || (!!rel && !rel.startsWith('..') && !isAbsolute(rel));
}

/**
 * Roots of marketplaces installed from a local directory rather than a clone.
 * @param {string} [configDir]
 * @returns {string[]}
 */
export function getDirectoryMarketplaceRoots(configDir = getClaudeConfigDir()) {
  const known = readJson(join(configDir, 'plugins', 'known_marketplaces.json'));
  if (!known || typeof known !== 'object') return [];

  const roots = [];
  for (const entry of Object.values(known)) {
    if (entry?.source?.source !== 'directory') continue;
    const path = entry.installLocation || entry.source.path;
    if (typeof path === 'string' && path.trim()) roots.push(path.trim());
  }
  return roots;
}

/**
 * True when `root` is a git working tree that also carries the OMC marketplace
 * manifest - i.e. the repo itself, loaded in place.
 * @param {string} root
 */
function isCheckoutRoot(root) {
  if (!existsSync(join(root, '.git'))) return false;
  const manifest = readJson(join(root, '.claude-plugin', 'marketplace.json'));
  return Array.isArray(manifest?.plugins)
    ? manifest.plugins.some(plugin => plugin?.name === 'oh-my-claudecode')
    : false;
}

/**
 * True when the given plugin root resolves to a local checkout.
 * @param {string | undefined | null} root
 * @param {string} [configDir]
 */
export function isLocalSourcePluginRoot(root, configDir = getClaudeConfigDir()) {
  if (!root || typeof root !== 'string') return false;
  if (getDirectoryMarketplaceRoots(configDir).some(marketplaceRoot => isInsideOrEqual(marketplaceRoot, root))) {
    return true;
  }
  return isCheckoutRoot(root);
}

/**
 * Version declared by the local checkout at `root`, or null.
 * @param {string} root
 */
export function getLocalSourceVersion(root) {
  if (!root || typeof root !== 'string') return null;

  const manifest = readJson(join(root, '.claude-plugin', 'marketplace.json'));
  const entry = Array.isArray(manifest?.plugins)
    ? manifest.plugins.find(plugin => plugin?.name === 'oh-my-claudecode')
    : null;
  const declared = typeof entry?.version === 'string' ? entry.version.trim() : '';
  if (declared) return declared;

  const pkg = readJson(join(root, 'package.json'));
  return typeof pkg?.version === 'string' && pkg.version.trim() ? pkg.version.trim() : null;
}
