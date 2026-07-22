import { readFileSync } from 'fs';
import { resolve } from 'path';
import { describe, expect, it } from 'vitest';

describe('.omc gitignore state contract', () => {
  it('ignores runtime .omc state while allowing project skills to be committed intentionally', () => {
    const gitignore = readFileSync(
      resolve(process.cwd(), '.gitignore'),
      'utf-8',
    )
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);

    // Nested .omc/ dirs (any depth) are always accidental and ignored via
    // '**/.omc/'; only the root-anchored '!/.omc/' re-includes the canonical
    // anchor. An unanchored '!.omc/' would re-include nested dirs too and
    // defeat the guard.
    expect(gitignore).toEqual(
      expect.arrayContaining([
        '**/.omc/',
        '!/.omc/',
        '.omc/*',
        '!.omc/skills/',
        '!.omc/skills/**',
      ]),
    );

    expect(gitignore.indexOf('**/.omc/')).toBeLessThan(
      gitignore.indexOf('!/.omc/'),
    );
    expect(gitignore.indexOf('!/.omc/')).toBeLessThan(
      gitignore.indexOf('.omc/*'),
    );
    expect(gitignore.indexOf('.omc/*')).toBeLessThan(
      gitignore.indexOf('!.omc/skills/'),
    );
    expect(gitignore.indexOf('!.omc/skills/')).toBeLessThan(
      gitignore.indexOf('!.omc/skills/**'),
    );
  });
});
