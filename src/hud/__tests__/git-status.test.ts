/**
 * Tests for git status HUD element
 *
 * Covers:
 * - getGitStatusCounts parsing of `git status --porcelain -b`
 * - renderGitStatus output formatting
 * - Cache behavior
 */

<<<<<<< HEAD
import { describe, it, expect, vi, beforeEach } from "vitest";
import { execSync } from "node:child_process";
||||||| 90f19265
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { execSync } from 'node:child_process';
=======
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { execFileSync } from 'node:child_process';
>>>>>>> main

vi.mock("node:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:child_process")>();
  return {
    ...actual,
    execFileSync: vi.fn(),
  };
});

import {
  getGitStatusCounts,
  renderGitStatus,
  resetGitCache,
} from "../elements/git.js";

const mockedExecFileSync = vi.mocked(execFileSync);

beforeEach(() => {
  vi.resetAllMocks();
  resetGitCache();
});

// ---------------------------------------------------------------------------
// getGitStatusCounts
// ---------------------------------------------------------------------------
<<<<<<< HEAD
describe("getGitStatusCounts", () => {
  it("returns zeros for clean repo", () => {
    mockedExecSync.mockReturnValue("## main...origin/main\n" as any);
    const counts = getGitStatusCounts("/tmp");
    expect(counts).toEqual({
      staged: 0,
      modified: 0,
      untracked: 0,
      ahead: 0,
      behind: 0,
    });
||||||| 90f19265
describe('getGitStatusCounts', () => {
  it('returns zeros for clean repo', () => {
    mockedExecSync.mockReturnValue('## main...origin/main\n' as any);
    const counts = getGitStatusCounts('/tmp');
    expect(counts).toEqual({ staged: 0, modified: 0, untracked: 0, ahead: 0, behind: 0 });
=======
describe('getGitStatusCounts', () => {
  it('returns zeros for clean repo', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main\n' as any);
    const counts = getGitStatusCounts('/tmp');
    expect(counts).toEqual({ staged: 0, modified: 0, untracked: 0, ahead: 0, behind: 0 });
>>>>>>> main
  });

<<<<<<< HEAD
  it("counts staged files", () => {
    mockedExecSync.mockReturnValue(
      "## main\nM  file1.ts\nA  file2.ts\n" as any,
    );
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('counts staged files', () => {
    mockedExecSync.mockReturnValue('## main\nM  file1.ts\nA  file2.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('counts staged files', () => {
    mockedExecFileSync.mockReturnValue('## main\nM  file1.ts\nA  file2.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.staged).toBe(2);
    expect(counts?.modified).toBe(0);
  });

<<<<<<< HEAD
  it("counts modified (unstaged) files", () => {
    mockedExecSync.mockReturnValue(
      "## main\n M file1.ts\n D file2.ts\n" as any,
    );
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('counts modified (unstaged) files', () => {
    mockedExecSync.mockReturnValue('## main\n M file1.ts\n D file2.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('counts modified (unstaged) files', () => {
    mockedExecFileSync.mockReturnValue('## main\n M file1.ts\n D file2.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.staged).toBe(0);
    expect(counts?.modified).toBe(2);
  });

<<<<<<< HEAD
  it("counts untracked files", () => {
    mockedExecSync.mockReturnValue(
      "## main\n?? newfile.ts\n?? another.ts\n?? third.ts\n" as any,
    );
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('counts untracked files', () => {
    mockedExecSync.mockReturnValue('## main\n?? newfile.ts\n?? another.ts\n?? third.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('counts untracked files', () => {
    mockedExecFileSync.mockReturnValue('## main\n?? newfile.ts\n?? another.ts\n?? third.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.untracked).toBe(3);
    expect(counts?.staged).toBe(0);
    expect(counts?.modified).toBe(0);
  });

  it("counts both staged and modified for same file", () => {
    // MM means staged + modified
<<<<<<< HEAD
    mockedExecSync.mockReturnValue("## main\nMM file.ts\n" as any);
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
    mockedExecSync.mockReturnValue('## main\nMM file.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
    mockedExecFileSync.mockReturnValue('## main\nMM file.ts\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.staged).toBe(1);
    expect(counts?.modified).toBe(1);
  });

<<<<<<< HEAD
  it("parses ahead count", () => {
    mockedExecSync.mockReturnValue("## main...origin/main [ahead 3]\n" as any);
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('parses ahead count', () => {
    mockedExecSync.mockReturnValue('## main...origin/main [ahead 3]\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('parses ahead count', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main [ahead 3]\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.ahead).toBe(3);
    expect(counts?.behind).toBe(0);
  });

<<<<<<< HEAD
  it("parses behind count", () => {
    mockedExecSync.mockReturnValue("## main...origin/main [behind 2]\n" as any);
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('parses behind count', () => {
    mockedExecSync.mockReturnValue('## main...origin/main [behind 2]\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('parses behind count', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main [behind 2]\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.ahead).toBe(0);
    expect(counts?.behind).toBe(2);
  });

<<<<<<< HEAD
  it("parses ahead and behind", () => {
    mockedExecSync.mockReturnValue(
      "## main...origin/main [ahead 5, behind 2]\n" as any,
    );
    const counts = getGitStatusCounts("/tmp");
||||||| 90f19265
  it('parses ahead and behind', () => {
    mockedExecSync.mockReturnValue('## main...origin/main [ahead 5, behind 2]\n' as any);
    const counts = getGitStatusCounts('/tmp');
=======
  it('parses ahead and behind', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main [ahead 5, behind 2]\n' as any);
    const counts = getGitStatusCounts('/tmp');
>>>>>>> main
    expect(counts?.ahead).toBe(5);
    expect(counts?.behind).toBe(2);
  });

<<<<<<< HEAD
  it("handles mixed status", () => {
    mockedExecSync.mockReturnValue(
      ("## feat...origin/feat [ahead 1, behind 3]\n" +
        "M  staged.ts\n" +
        " M modified.ts\n" +
        "?? new.ts\n" +
        "A  added.ts\n" +
        "D  deleted.ts\n" +
        " D removed.ts\n") as any,
    );
    const counts = getGitStatusCounts("/tmp");
    expect(counts).toEqual({
      staged: 3,
      modified: 2,
      untracked: 1,
      ahead: 1,
      behind: 3,
    });
||||||| 90f19265
  it('handles mixed status', () => {
    mockedExecSync.mockReturnValue((
      '## feat...origin/feat [ahead 1, behind 3]\n' +
      'M  staged.ts\n' +
      ' M modified.ts\n' +
      '?? new.ts\n' +
      'A  added.ts\n' +
      'D  deleted.ts\n' +
      ' D removed.ts\n'
    ) as any);
    const counts = getGitStatusCounts('/tmp');
    expect(counts).toEqual({ staged: 3, modified: 2, untracked: 1, ahead: 1, behind: 3 });
=======
  it('handles mixed status', () => {
    mockedExecFileSync.mockReturnValue((
      '## feat...origin/feat [ahead 1, behind 3]\n' +
      'M  staged.ts\n' +
      ' M modified.ts\n' +
      '?? new.ts\n' +
      'A  added.ts\n' +
      'D  deleted.ts\n' +
      ' D removed.ts\n'
    ) as any);
    const counts = getGitStatusCounts('/tmp');
    expect(counts).toEqual({ staged: 3, modified: 2, untracked: 1, ahead: 1, behind: 3 });
>>>>>>> main
  });

<<<<<<< HEAD
  it("returns null on git error", () => {
    mockedExecSync.mockImplementation(() => {
      throw new Error("not a git repo");
    });
    expect(getGitStatusCounts("/tmp")).toBeNull();
||||||| 90f19265
  it('returns null on git error', () => {
    mockedExecSync.mockImplementation(() => { throw new Error('not a git repo'); });
    expect(getGitStatusCounts('/tmp')).toBeNull();
=======
  it('returns null on git error', () => {
    mockedExecFileSync.mockImplementation(() => { throw new Error('not a git repo'); });
    expect(getGitStatusCounts('/tmp')).toBeNull();
>>>>>>> main
  });

<<<<<<< HEAD
  it("returns cached result on second call", () => {
    mockedExecSync.mockReturnValue("## main\n?? file.ts\n" as any);
    getGitStatusCounts("/tmp");
    getGitStatusCounts("/tmp");
    expect(mockedExecSync).toHaveBeenCalledTimes(1);
||||||| 90f19265
  it('returns cached result on second call', () => {
    mockedExecSync.mockReturnValue('## main\n?? file.ts\n' as any);
    getGitStatusCounts('/tmp');
    getGitStatusCounts('/tmp');
    expect(mockedExecSync).toHaveBeenCalledTimes(1);
=======
  it('returns cached result on second call', () => {
    mockedExecFileSync.mockReturnValue('## main\n?? file.ts\n' as any);
    getGitStatusCounts('/tmp');
    getGitStatusCounts('/tmp');
    expect(mockedExecFileSync).toHaveBeenCalledTimes(1);
>>>>>>> main
  });

<<<<<<< HEAD
  it("disables optional git locks for background HUD polling", () => {
    mockedExecSync.mockReturnValue("## main\n" as any);
    getGitStatusCounts("/tmp");
    expect(mockedExecSync).toHaveBeenCalledWith(
      "git --no-optional-locks status --porcelain -b",
      expect.objectContaining({ cwd: "/tmp" }),
||||||| 90f19265
  it('disables optional git locks for background HUD polling', () => {
    mockedExecSync.mockReturnValue('## main\n' as any);
    getGitStatusCounts('/tmp');
    expect(mockedExecSync).toHaveBeenCalledWith(
      'git --no-optional-locks status --porcelain -b',
      expect.objectContaining({ cwd: '/tmp' }),
=======
  it('disables optional git locks for background HUD polling', () => {
    mockedExecFileSync.mockReturnValue('## main\n' as any);
    getGitStatusCounts('/tmp');
    expect(mockedExecFileSync).toHaveBeenCalledWith(
      'git',
      ['--no-optional-locks', 'status', '--porcelain', '-b'],
      expect.objectContaining({ cwd: '/tmp', windowsHide: true }),
>>>>>>> main
    );
  });
});

// ---------------------------------------------------------------------------
// renderGitStatus
// ---------------------------------------------------------------------------
<<<<<<< HEAD
describe("renderGitStatus", () => {
  it("returns null for clean repo", () => {
    mockedExecSync.mockReturnValue("## main...origin/main\n" as any);
    expect(renderGitStatus("/tmp")).toBeNull();
||||||| 90f19265
describe('renderGitStatus', () => {
  it('returns null for clean repo', () => {
    mockedExecSync.mockReturnValue('## main...origin/main\n' as any);
    expect(renderGitStatus('/tmp')).toBeNull();
=======
describe('renderGitStatus', () => {
  it('returns null for clean repo', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main\n' as any);
    expect(renderGitStatus('/tmp')).toBeNull();
>>>>>>> main
  });

<<<<<<< HEAD
  it("returns null on git error", () => {
    mockedExecSync.mockImplementation(() => {
      throw new Error("fail");
    });
    expect(renderGitStatus("/tmp")).toBeNull();
||||||| 90f19265
  it('returns null on git error', () => {
    mockedExecSync.mockImplementation(() => { throw new Error('fail'); });
    expect(renderGitStatus('/tmp')).toBeNull();
=======
  it('returns null on git error', () => {
    mockedExecFileSync.mockImplementation(() => { throw new Error('fail'); });
    expect(renderGitStatus('/tmp')).toBeNull();
>>>>>>> main
  });

<<<<<<< HEAD
  it("shows staged count with + prefix", () => {
    mockedExecSync.mockReturnValue("## main\nA  file.ts\n" as any);
    const result = renderGitStatus("/tmp")!;
    expect(result).toContain("+");
    expect(result).toContain("1");
||||||| 90f19265
  it('shows staged count with + prefix', () => {
    mockedExecSync.mockReturnValue('## main\nA  file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('+');
    expect(result).toContain('1');
=======
  it('shows staged count with + prefix', () => {
    mockedExecFileSync.mockReturnValue('## main\nA  file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('+');
    expect(result).toContain('1');
>>>>>>> main
  });

<<<<<<< HEAD
  it("shows modified count with ! prefix", () => {
    mockedExecSync.mockReturnValue("## main\n M file.ts\n" as any);
    const result = renderGitStatus("/tmp")!;
    expect(result).toContain("!");
    expect(result).toContain("1");
||||||| 90f19265
  it('shows modified count with ! prefix', () => {
    mockedExecSync.mockReturnValue('## main\n M file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('!');
    expect(result).toContain('1');
=======
  it('shows modified count with ! prefix', () => {
    mockedExecFileSync.mockReturnValue('## main\n M file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('!');
    expect(result).toContain('1');
>>>>>>> main
  });

<<<<<<< HEAD
  it("shows untracked count with ? prefix", () => {
    mockedExecSync.mockReturnValue("## main\n?? file.ts\n" as any);
    const result = renderGitStatus("/tmp")!;
    expect(result).toContain("?");
    expect(result).toContain("1");
||||||| 90f19265
  it('shows untracked count with ? prefix', () => {
    mockedExecSync.mockReturnValue('## main\n?? file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('?');
    expect(result).toContain('1');
=======
  it('shows untracked count with ? prefix', () => {
    mockedExecFileSync.mockReturnValue('## main\n?? file.ts\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('?');
    expect(result).toContain('1');
>>>>>>> main
  });

<<<<<<< HEAD
  it("shows ahead with ⇡", () => {
    mockedExecSync.mockReturnValue("## main...origin/main [ahead 2]\n" as any);
    const result = renderGitStatus("/tmp")!;
    expect(result).toContain("⇡");
    expect(result).toContain("2");
||||||| 90f19265
  it('shows ahead with ⇡', () => {
    mockedExecSync.mockReturnValue('## main...origin/main [ahead 2]\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('⇡');
    expect(result).toContain('2');
=======
  it('shows ahead with ⇡', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main [ahead 2]\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('⇡');
    expect(result).toContain('2');
>>>>>>> main
  });

<<<<<<< HEAD
  it("shows behind with ⇣", () => {
    mockedExecSync.mockReturnValue("## main...origin/main [behind 4]\n" as any);
    const result = renderGitStatus("/tmp")!;
    expect(result).toContain("⇣");
    expect(result).toContain("4");
||||||| 90f19265
  it('shows behind with ⇣', () => {
    mockedExecSync.mockReturnValue('## main...origin/main [behind 4]\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('⇣');
    expect(result).toContain('4');
=======
  it('shows behind with ⇣', () => {
    mockedExecFileSync.mockReturnValue('## main...origin/main [behind 4]\n' as any);
    const result = renderGitStatus('/tmp')!;
    expect(result).toContain('⇣');
    expect(result).toContain('4');
>>>>>>> main
  });

<<<<<<< HEAD
  it("uses configured status labels without changing counts", () => {
    mockedExecSync.mockReturnValue(
      ("## main...origin/main [ahead 2, behind 4]\n" +
        "A  staged.ts\n" +
        " M modified.ts\n" +
        "?? new.ts\n") as any,
    );
    const result = renderGitStatus("/tmp", {
      staged: "已暂存",
      modified: "已修改",
      untracked: "未跟踪",
      ahead: "领先",
      behind: "落后",
||||||| 90f19265

  it('uses configured status labels without changing counts', () => {
    mockedExecSync.mockReturnValue((
      '## main...origin/main [ahead 2, behind 4]\n' +
      'A  staged.ts\n' +
      ' M modified.ts\n' +
      '?? new.ts\n'
    ) as any);
    const result = renderGitStatus('/tmp', {
      staged: '已暂存',
      modified: '已修改',
      untracked: '未跟踪',
      ahead: '领先',
      behind: '落后',
=======

  it('uses configured status labels without changing counts', () => {
    mockedExecFileSync.mockReturnValue((
      '## main...origin/main [ahead 2, behind 4]\n' +
      'A  staged.ts\n' +
      ' M modified.ts\n' +
      '?? new.ts\n'
    ) as any);
    const result = renderGitStatus('/tmp', {
      staged: '已暂存',
      modified: '已修改',
      untracked: '未跟踪',
      ahead: '领先',
      behind: '落后',
>>>>>>> main
    })!;
    expect(result).toContain("已暂存");
    expect(result).toContain("已修改");
    expect(result).toContain("未跟踪");
    expect(result).toContain("领先");
    expect(result).toContain("落后");
  });
});
