import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  getGitRepoName,
  getGitBranch,
  getWorktreeInfo,
  renderGitRepo,
  renderGitBranch,
  resetGitCache,
} from "../../hud/elements/git.js";

<<<<<<< HEAD
// Mock child_process.execSync
vi.mock("node:child_process", () => ({
  execSync: vi.fn(),
||||||| 90f19265
// Mock child_process.execSync
vi.mock('node:child_process', () => ({
  execSync: vi.fn(),
=======
// Mock child_process.execFileSync
vi.mock('node:child_process', () => ({
  execFileSync: vi.fn(),
>>>>>>> main
}));

<<<<<<< HEAD
import { execSync } from "node:child_process";
const mockExecSync = vi.mocked(execSync);
||||||| 90f19265
import { execSync } from 'node:child_process';
const mockExecSync = vi.mocked(execSync);
=======
import { execFileSync } from 'node:child_process';
const mockExecFileSync = vi.mocked(execFileSync);
>>>>>>> main

describe("git elements", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetGitCache();
  });

<<<<<<< HEAD
  describe("getGitRepoName", () => {
    it("extracts repo name from HTTPS URL", () => {
      mockExecSync.mockReturnValue("https://github.com/user/my-repo.git\n");
      expect(getGitRepoName()).toBe("my-repo");
||||||| 90f19265
  describe('getGitRepoName', () => {
    it('extracts repo name from HTTPS URL', () => {
      mockExecSync.mockReturnValue('https://github.com/user/my-repo.git\n');
      expect(getGitRepoName()).toBe('my-repo');
=======
  describe('getGitRepoName', () => {
    it('extracts repo name from HTTPS URL', () => {
      mockExecFileSync.mockReturnValue('https://github.com/user/my-repo.git\n');
      expect(getGitRepoName()).toBe('my-repo');
>>>>>>> main
    });

<<<<<<< HEAD
    it("extracts repo name from HTTPS URL without .git", () => {
      mockExecSync.mockReturnValue("https://github.com/user/my-repo\n");
      expect(getGitRepoName()).toBe("my-repo");
||||||| 90f19265
    it('extracts repo name from HTTPS URL without .git', () => {
      mockExecSync.mockReturnValue('https://github.com/user/my-repo\n');
      expect(getGitRepoName()).toBe('my-repo');
=======
    it('extracts repo name from HTTPS URL without .git', () => {
      mockExecFileSync.mockReturnValue('https://github.com/user/my-repo\n');
      expect(getGitRepoName()).toBe('my-repo');
>>>>>>> main
    });

<<<<<<< HEAD
    it("extracts repo name from SSH URL", () => {
      mockExecSync.mockReturnValue("git@github.com:user/my-repo.git\n");
      expect(getGitRepoName()).toBe("my-repo");
||||||| 90f19265
    it('extracts repo name from SSH URL', () => {
      mockExecSync.mockReturnValue('git@github.com:user/my-repo.git\n');
      expect(getGitRepoName()).toBe('my-repo');
=======
    it('extracts repo name from SSH URL', () => {
      mockExecFileSync.mockReturnValue('git@github.com:user/my-repo.git\n');
      expect(getGitRepoName()).toBe('my-repo');
>>>>>>> main
    });

<<<<<<< HEAD
    it("extracts repo name from SSH URL without .git", () => {
      mockExecSync.mockReturnValue("git@github.com:user/my-repo\n");
      expect(getGitRepoName()).toBe("my-repo");
||||||| 90f19265
    it('extracts repo name from SSH URL without .git', () => {
      mockExecSync.mockReturnValue('git@github.com:user/my-repo\n');
      expect(getGitRepoName()).toBe('my-repo');
=======
    it('extracts repo name from SSH URL without .git', () => {
      mockExecFileSync.mockReturnValue('git@github.com:user/my-repo\n');
      expect(getGitRepoName()).toBe('my-repo');
>>>>>>> main
    });

<<<<<<< HEAD
    it("returns null when git command fails", () => {
      mockExecSync.mockImplementation(() => {
        throw new Error("Not a git repository");
||||||| 90f19265
    it('returns null when git command fails', () => {
      mockExecSync.mockImplementation(() => {
        throw new Error('Not a git repository');
=======
    it('returns null when git command fails', () => {
      mockExecFileSync.mockImplementation(() => {
        throw new Error('Not a git repository');
>>>>>>> main
      });
      expect(getGitRepoName()).toBeNull();
    });

<<<<<<< HEAD
    it("returns null for empty output", () => {
      mockExecSync.mockReturnValue("");
||||||| 90f19265
    it('returns null for empty output', () => {
      mockExecSync.mockReturnValue('');
=======
    it('returns null for empty output', () => {
      mockExecFileSync.mockReturnValue('');
>>>>>>> main
      expect(getGitRepoName()).toBeNull();
    });

<<<<<<< HEAD
    it("passes cwd option to execSync", () => {
      mockExecSync.mockReturnValue("https://github.com/user/repo.git\n");
      getGitRepoName("/some/path");
      expect(mockExecSync).toHaveBeenCalledWith(
        "git remote get-url origin",
        expect.objectContaining({ cwd: "/some/path" }),
||||||| 90f19265
    it('passes cwd option to execSync', () => {
      mockExecSync.mockReturnValue('https://github.com/user/repo.git\n');
      getGitRepoName('/some/path');
      expect(mockExecSync).toHaveBeenCalledWith(
        'git remote get-url origin',
        expect.objectContaining({ cwd: '/some/path' })
=======
    it('passes cwd option to execFileSync', () => {
      mockExecFileSync.mockReturnValue('https://github.com/user/repo.git\n');
      getGitRepoName('/some/path');
      expect(mockExecFileSync).toHaveBeenCalledWith(
        'git',
        ['remote', 'get-url', 'origin'],
        expect.objectContaining({ cwd: '/some/path', windowsHide: true })
>>>>>>> main
      );
    });
  });

<<<<<<< HEAD
  describe("getGitBranch", () => {
    it("returns current branch name", () => {
      mockExecSync.mockReturnValue("main\n");
      expect(getGitBranch()).toBe("main");
||||||| 90f19265
  describe('getGitBranch', () => {
    it('returns current branch name', () => {
      mockExecSync.mockReturnValue('main\n');
      expect(getGitBranch()).toBe('main');
=======
  describe('getGitBranch', () => {
    it('returns current branch name', () => {
      mockExecFileSync.mockReturnValue('main\n');
      expect(getGitBranch()).toBe('main');
>>>>>>> main
    });

<<<<<<< HEAD
    it("handles feature branch names", () => {
      mockExecSync.mockReturnValue("feature/my-feature\n");
      expect(getGitBranch()).toBe("feature/my-feature");
||||||| 90f19265
    it('handles feature branch names', () => {
      mockExecSync.mockReturnValue('feature/my-feature\n');
      expect(getGitBranch()).toBe('feature/my-feature');
=======
    it('handles feature branch names', () => {
      mockExecFileSync.mockReturnValue('feature/my-feature\n');
      expect(getGitBranch()).toBe('feature/my-feature');
>>>>>>> main
    });

<<<<<<< HEAD
    it("returns null when git command fails", () => {
      mockExecSync.mockImplementation(() => {
        throw new Error("Not a git repository");
||||||| 90f19265
    it('returns null when git command fails', () => {
      mockExecSync.mockImplementation(() => {
        throw new Error('Not a git repository');
=======
    it('returns null when git command fails', () => {
      mockExecFileSync.mockImplementation(() => {
        throw new Error('Not a git repository');
>>>>>>> main
      });
      expect(getGitBranch()).toBeNull();
    });

<<<<<<< HEAD
    it("returns null for empty output", () => {
      mockExecSync.mockReturnValue("");
||||||| 90f19265
    it('returns null for empty output', () => {
      mockExecSync.mockReturnValue('');
=======
    it('returns null for empty output', () => {
      mockExecFileSync.mockReturnValue('');
>>>>>>> main
      expect(getGitBranch()).toBeNull();
    });

<<<<<<< HEAD
    it("passes cwd option to execSync", () => {
      mockExecSync.mockReturnValue("main\n");
      getGitBranch("/some/path");
      expect(mockExecSync).toHaveBeenCalledWith(
        "git branch --show-current",
        expect.objectContaining({ cwd: "/some/path" }),
||||||| 90f19265
    it('passes cwd option to execSync', () => {
      mockExecSync.mockReturnValue('main\n');
      getGitBranch('/some/path');
      expect(mockExecSync).toHaveBeenCalledWith(
        'git branch --show-current',
        expect.objectContaining({ cwd: '/some/path' })
=======
    it('passes cwd option to execFileSync', () => {
      mockExecFileSync.mockReturnValue('main\n');
      getGitBranch('/some/path');
      expect(mockExecFileSync).toHaveBeenCalledWith(
        'git',
        ['branch', '--show-current'],
        expect.objectContaining({ cwd: '/some/path', windowsHide: true })
>>>>>>> main
      );
    });
  });

<<<<<<< HEAD
  describe("renderGitRepo", () => {
    it("renders formatted repo name", () => {
      mockExecSync.mockReturnValue("https://github.com/user/my-repo.git\n");
||||||| 90f19265
  describe('renderGitRepo', () => {
    it('renders formatted repo name', () => {
      mockExecSync.mockReturnValue('https://github.com/user/my-repo.git\n');
=======
  describe('renderGitRepo', () => {
    it('renders formatted repo name', () => {
      mockExecFileSync.mockReturnValue('https://github.com/user/my-repo.git\n');
>>>>>>> main
      const result = renderGitRepo();
      expect(result).toContain("repo:");
      expect(result).toContain("my-repo");
    });

<<<<<<< HEAD
    it("returns null when repo not available", () => {
      mockExecSync.mockImplementation(() => {
        throw new Error("Not a git repository");
||||||| 90f19265
    it('returns null when repo not available', () => {
      mockExecSync.mockImplementation(() => {
        throw new Error('Not a git repository');
=======
    it('returns null when repo not available', () => {
      mockExecFileSync.mockImplementation(() => {
        throw new Error('Not a git repository');
>>>>>>> main
      });
      expect(renderGitRepo()).toBeNull();
    });

<<<<<<< HEAD
    it("applies styling", () => {
      mockExecSync.mockReturnValue("https://github.com/user/repo.git\n");
||||||| 90f19265
    it('applies styling', () => {
      mockExecSync.mockReturnValue('https://github.com/user/repo.git\n');
=======
    it('applies styling', () => {
      mockExecFileSync.mockReturnValue('https://github.com/user/repo.git\n');
>>>>>>> main
      const result = renderGitRepo();
      expect(result).toContain("\x1b["); // contains ANSI escape codes
    });
  });

<<<<<<< HEAD
  describe("getWorktreeInfo", () => {
    it("returns isWorktree false for normal repo", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git rev-parse --git-dir") return ".git\n";
        if (cmd === "git rev-parse --git-common-dir") return ".git\n";
        return "";
||||||| 90f19265
  describe('getWorktreeInfo', () => {
    it('returns isWorktree false for normal repo', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git rev-parse --git-dir') return '.git\n';
        if (cmd === 'git rev-parse --git-common-dir') return '.git\n';
        return '';
=======
  describe('getWorktreeInfo', () => {
    it('returns isWorktree false for normal repo', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'rev-parse --git-dir') return '.git\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '.git\n';
        return '';
>>>>>>> main
      });
      const result = getWorktreeInfo("/some/repo");
      expect(result.isWorktree).toBe(false);
      expect(result.worktreeName).toBeNull();
    });

<<<<<<< HEAD
    it("detects linked worktree and extracts worktree name from git-dir", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git rev-parse --git-dir")
          return "/main-repo/.git/worktrees/my-wt\n";
        if (cmd === "git rev-parse --git-common-dir")
          return "/main-repo/.git\n";
        return "";
||||||| 90f19265
    it('detects linked worktree and extracts worktree name from git-dir', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git rev-parse --git-dir') return '/main-repo/.git/worktrees/my-wt\n';
        if (cmd === 'git rev-parse --git-common-dir') return '/main-repo/.git\n';
        return '';
=======
    it('detects linked worktree and extracts worktree name from git-dir', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'rev-parse --git-dir') return '/main-repo/.git/worktrees/my-wt\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '/main-repo/.git\n';
        return '';
>>>>>>> main
      });

      const result = getWorktreeInfo("/some/worktree");
      expect(result.isWorktree).toBe(true);
      expect(result.worktreeName).toBe("my-wt");
    });

<<<<<<< HEAD
    it("extracts worktree name with nested path segments", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git rev-parse --git-dir")
          return "/repo/.git/worktrees/feature-NAVERCAFE-12345\n";
        if (cmd === "git rev-parse --git-common-dir") return "/repo/.git\n";
        return "";
||||||| 90f19265
    it('extracts worktree name with nested path segments', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git rev-parse --git-dir') return '/repo/.git/worktrees/feature-NAVERCAFE-12345\n';
        if (cmd === 'git rev-parse --git-common-dir') return '/repo/.git\n';
        return '';
=======
    it('extracts worktree name with nested path segments', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'rev-parse --git-dir') return '/repo/.git/worktrees/feature-NAVERCAFE-12345\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '/repo/.git\n';
        return '';
>>>>>>> main
      });

      const result = getWorktreeInfo("/some/worktree");
      expect(result.isWorktree).toBe(true);
      expect(result.worktreeName).toBe("feature-NAVERCAFE-12345");
    });

<<<<<<< HEAD
    it("returns not a worktree when git commands fail", () => {
      mockExecSync.mockImplementation(() => {
        throw new Error("Not a git repository");
||||||| 90f19265
    it('returns not a worktree when git commands fail', () => {
      mockExecSync.mockImplementation(() => {
        throw new Error('Not a git repository');
=======
    it('returns not a worktree when git commands fail', () => {
      mockExecFileSync.mockImplementation(() => {
        throw new Error('Not a git repository');
>>>>>>> main
      });
      const result = getWorktreeInfo();
      expect(result.isWorktree).toBe(false);
      expect(result.worktreeName).toBeNull();
    });

<<<<<<< HEAD
    it("caches result for same cwd", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git rev-parse --git-dir") return ".git\n";
        if (cmd === "git rev-parse --git-common-dir") return ".git\n";
        return "";
||||||| 90f19265
    it('caches result for same cwd', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git rev-parse --git-dir') return '.git\n';
        if (cmd === 'git rev-parse --git-common-dir') return '.git\n';
        return '';
=======
    it('caches result for same cwd', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'rev-parse --git-dir') return '.git\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '.git\n';
        return '';
>>>>>>> main
      });

      getWorktreeInfo("/cached/path");
      getWorktreeInfo("/cached/path");

<<<<<<< HEAD
      const gitDirCalls = mockExecSync.mock.calls.filter(
        (c) => c[0] === "git rev-parse --git-dir",
      );
||||||| 90f19265
      const gitDirCalls = mockExecSync.mock.calls.filter(c => c[0] === 'git rev-parse --git-dir');
=======
      const gitDirCalls = mockExecFileSync.mock.calls.filter(c => Array.isArray(c[1]) && c[1].join(' ') === 'rev-parse --git-dir');
>>>>>>> main
      expect(gitDirCalls).toHaveLength(1);
    });
  });

<<<<<<< HEAD
  describe("renderGitBranch", () => {
    it("renders formatted branch name", () => {
      mockExecSync.mockReturnValue("main\n");
||||||| 90f19265
  describe('renderGitBranch', () => {
    it('renders formatted branch name', () => {
      mockExecSync.mockReturnValue('main\n');
=======
  describe('renderGitBranch', () => {
    it('renders formatted branch name', () => {
      mockExecFileSync.mockReturnValue('main\n');
>>>>>>> main
      const result = renderGitBranch();
      expect(result).toContain("branch:");
      expect(result).toContain("main");
    });

<<<<<<< HEAD
    it("returns null when branch not available", () => {
      mockExecSync.mockImplementation(() => {
        throw new Error("Not a git repository");
||||||| 90f19265
    it('returns null when branch not available', () => {
      mockExecSync.mockImplementation(() => {
        throw new Error('Not a git repository');
=======
    it('returns null when branch not available', () => {
      mockExecFileSync.mockImplementation(() => {
        throw new Error('Not a git repository');
>>>>>>> main
      });
      expect(renderGitBranch()).toBeNull();
    });

<<<<<<< HEAD
    it("applies styling", () => {
      mockExecSync.mockReturnValue("main\n");
||||||| 90f19265
    it('applies styling', () => {
      mockExecSync.mockReturnValue('main\n');
=======
    it('applies styling', () => {
      mockExecFileSync.mockReturnValue('main\n');
>>>>>>> main
      const result = renderGitBranch();
      expect(result).toContain("\x1b["); // contains ANSI escape codes
    });

<<<<<<< HEAD
    it("shows worktree suffix with worktree name when in a linked worktree", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git branch --show-current") return "feature-x\n";
        if (cmd === "git rev-parse --git-dir")
          return "/main/.git/worktrees/my-wt\n";
        if (cmd === "git rev-parse --git-common-dir") return "/main/.git\n";
        return "";
||||||| 90f19265
    it('shows worktree suffix with worktree name when in a linked worktree', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git branch --show-current') return 'feature-x\n';
        if (cmd === 'git rev-parse --git-dir') return '/main/.git/worktrees/my-wt\n';
        if (cmd === 'git rev-parse --git-common-dir') return '/main/.git\n';
        return '';
=======
    it('shows worktree suffix with worktree name when in a linked worktree', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'branch --show-current') return 'feature-x\n';
        if (args?.join(' ') === 'rev-parse --git-dir') return '/main/.git/worktrees/my-wt\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '/main/.git\n';
        return '';
>>>>>>> main
      });

      const result = renderGitBranch("/some/worktree");
      expect(result).toContain("branch:");
      expect(result).toContain("feature-x");
      expect(result).toContain("wt:");
      expect(result).toContain("my-wt");
    });

<<<<<<< HEAD
    it("does not show worktree suffix in normal repo", () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === "git branch --show-current") return "main\n";
        if (cmd === "git rev-parse --git-dir") return ".git\n";
        if (cmd === "git rev-parse --git-common-dir") return ".git\n";
        return "";
||||||| 90f19265
    it('does not show worktree suffix in normal repo', () => {
      mockExecSync.mockImplementation((cmd: string) => {
        if (cmd === 'git branch --show-current') return 'main\n';
        if (cmd === 'git rev-parse --git-dir') return '.git\n';
        if (cmd === 'git rev-parse --git-common-dir') return '.git\n';
        return '';
=======
    it('does not show worktree suffix in normal repo', () => {
      mockExecFileSync.mockImplementation((_file: string, args?: readonly string[]) => {
        if (args?.join(' ') === 'branch --show-current') return 'main\n';
        if (args?.join(' ') === 'rev-parse --git-dir') return '.git\n';
        if (args?.join(' ') === 'rev-parse --git-common-dir') return '.git\n';
        return '';
>>>>>>> main
      });

      const result = renderGitBranch("/some/repo");
      expect(result).toContain("branch:");
      expect(result).toContain("main");
      expect(result).not.toContain("wt:");
    });
  });
});
