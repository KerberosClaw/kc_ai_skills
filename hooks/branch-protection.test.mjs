// Tests for branch-protection.js. No dependencies beyond Node and git.
// Run: node --test hooks/branch-protection.test.mjs
//
// Builds throwaway repos under a temporary HOME and runs the hook as a child
// process with that HOME, so the real ~/.claude/branch-protection-skip.txt is
// never read or touched.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const HOOK = path.join(HERE, 'branch-protection.js');
const require = createRequire(import.meta.url);
const bp = require('./branch-protection.js');

let TMP, HOME, MAIN, WT, WT_SPACE, SOLO, PLAIN;

function cleanEnv() {
  const env = { ...process.env, HOME, GIT_CONFIG_NOSYSTEM: '1' };
  for (const k of Object.keys(env)) if (k.startsWith('GIT_') && k !== 'GIT_CONFIG_NOSYSTEM') delete env[k];
  return env;
}

function git(cwd, ...args) {
  const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false', ...args],
    { cwd, encoding: 'utf8', env: cleanEnv() });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout.trim();
}

function makeRepo(dir) {
  fs.mkdirSync(dir, { recursive: true });
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, 'commit', '-q', '--allow-empty', '-m', 'init');
}

before(() => {
  TMP = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'bp-test-')));
  HOME = path.join(TMP, 'home');
  MAIN = path.join(HOME, 'dev', 'proj');                      // main checkout, on main
  WT = path.join(MAIN, '.claude', 'worktrees', 'feat');       // nested worktree, like real usage
  WT_SPACE = path.join(HOME, 'dev', 'proj wt');               // worktree path containing a space
  SOLO = path.join(HOME, 'dev', 'solo');                      // listed in the skip file, on main
  PLAIN = path.join(HOME, 'plain');                           // not a git repo
  makeRepo(MAIN);
  git(MAIN, 'worktree', 'add', '-q', '-b', 'feature/x', WT);
  git(MAIN, 'worktree', 'add', '-q', '-b', 'feature/space', WT_SPACE);
  makeRepo(SOLO);
  fs.mkdirSync(PLAIN, { recursive: true });
  fs.mkdirSync(path.join(HOME, '.claude'), { recursive: true });
  fs.writeFileSync(path.join(HOME, '.claude', 'branch-protection-skip.txt'), '# test skip list\n~/dev/solo\n');
});

after(() => { if (TMP) fs.rmSync(TMP, { recursive: true, force: true }); });

function run(command, cwd, { omitCwd = false, processCwd } = {}) {
  const payload = { session_id: 't', hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command } };
  if (!omitCwd) payload.cwd = cwd;
  const input = JSON.stringify(payload);
  const r = spawnSync(process.execPath, [HOOK], { input, encoding: 'utf8', env: cleanEnv(), cwd: processCwd || TMP });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, input };
}

function allowed(command, cwd, opts) {
  const r = run(command, cwd, opts);
  assert.equal(r.status, 0, `expected allow: ${command}\nstderr: ${r.stderr}`);
  assert.equal(r.stdout, r.input, 'allowed commands must echo stdin to stdout');
  assert.doesNotMatch(r.stderr, /BLOCKED/);
  return r;
}

function blocked(command, cwd, opts) {
  const r = run(command, cwd, opts);
  assert.equal(r.status, 2, `expected block: ${command}\nstderr: ${r.stderr}`);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /\[Hook\] BLOCKED/);
  return r;
}

const q = (p) => `"${p}"`;

describe('commit: directory is the one the command acts on', () => {
  test('cwd main, cd <worktree> && git commit → allow', () => {
    allowed(`cd ${WT} && git add -A && git commit -m x`, MAIN);
  });
  test('cwd main, git -C <worktree> commit → allow', () => {
    allowed(`git -C ${WT} commit -m x`, MAIN);
  });
  test('cwd worktree, git -C <main> commit → block', () => {
    const r = blocked(`git -C ${MAIN} commit -m x`, WT);
    assert.ok(r.stderr.includes(`Checked: ${MAIN}, branch 'main'`), r.stderr);
  });
  test('cwd worktree, cd <main> && git commit → block', () => {
    blocked(`cd ${MAIN} && git commit -m x`, WT);
  });
  test('cwd main, git commit → block, message names dir and branch', () => {
    const r = blocked('git commit -m x', MAIN);
    assert.match(r.stderr, /You are on 'main'/);
    assert.ok(r.stderr.includes(`Checked: ${MAIN}, branch 'main'`), r.stderr);
    assert.match(r.stderr, /git checkout -b feature\/<short-name>/);
  });
  test('cwd main, git commit --amend --no-edit → allow (unchanged exception)', () => {
    allowed('git commit --amend --no-edit', MAIN);
    allowed('git commit --no-edit --amend', MAIN);
  });
  test('cwd main, git commit --amend (with edit) → block', () => {
    blocked('git commit --amend -m y', MAIN);
  });
  test('git -c user.name=x commit on main → block', () => {
    blocked('git -c user.name=x commit -m x', MAIN);
  });
  test('other global options before commit → still detected', () => {
    blocked('git --no-pager -c a.b=c commit -m x', MAIN);
    blocked(`git --git-dir=${MAIN}/.git --work-tree=${MAIN} commit -m x`, WT);
    blocked(`git --git-dir ${MAIN}/.git commit -m x`, PLAIN);
    allowed(`git --no-pager -C ${WT} commit -m x`, MAIN);
  });
  test('-C is cumulative and relative to the previous one', () => {
    allowed('git -C .claude -C worktrees/feat commit -m x', MAIN);
    blocked('git -C .claude/worktrees/feat -C ../../.. commit -m x', MAIN);
  });
  test('relative cd, cd - and chained cds', () => {
    allowed('cd .claude/worktrees/feat && git commit -m x', MAIN);
    blocked(`cd ${WT} && cd - && git commit -m x`, MAIN);
    allowed(`cd ${MAIN}; cd ${WT}; git commit -m x`, MAIN);
  });
  test('env-var prefix and wrappers in front of git', () => {
    blocked('FOO=1 GIT_EDITOR=true git commit -m x', MAIN);
    blocked('env FOO=1 git commit -m x', MAIN);
    blocked('command git commit -m x', MAIN);
    allowed(`FOO=1 git -C ${WT} commit -m x`, MAIN);
  });
  test('GIT_DIR / GIT_WORK_TREE prefix', () => {
    blocked(`GIT_DIR=${MAIN}/.git GIT_WORK_TREE=${MAIN} git commit -m x`, WT);
    blocked('GIT_DIR=~/dev/proj/.git git commit -m x', WT);
    blocked('git --git-dir=~/dev/proj/.git --work-tree=~/dev/proj commit -m x', WT);
  });
  test('subshell cd does not leak out', () => {
    allowed(`(cd ${WT} && git commit -m x)`, MAIN);
    blocked(`(cd ${WT}); git commit -m x`, MAIN);
  });
  test('bash -c / sh -c bodies are parsed', () => {
    blocked(`bash -c 'git commit -m x'`, MAIN);
    allowed(`bash -lc "cd ${WT} && git commit -m x"`, MAIN);
  });
  test('every git call in a chain is checked', () => {
    blocked(`git -C ${WT} commit -m a && git -C ${MAIN} commit -m b`, WT);
    blocked(`git -C ${WT} status\ngit commit -m b`, MAIN);
  });
  test('directory that does not exist yet → nearest existing parent', () => {
    blocked(`cd ${MAIN}/newdir && git commit -m x`, WT);
  });
});

describe('paths: tilde, quotes, spaces', () => {
  test('tilde expansion', () => {
    allowed('cd ~/dev/proj/.claude/worktrees/feat && git commit -m x', MAIN);
    allowed('git -C ~/dev/proj/.claude/worktrees/feat commit -m x', MAIN);
    blocked('git -C ~/dev/proj commit -m x', WT);
    allowed('git -C $HOME/dev/proj/.claude/worktrees/feat commit -m x', MAIN);
    allowed('git -C "${HOME}/dev/proj/.claude/worktrees/feat" commit -m x', MAIN);
  });
  test('double / single quoted paths', () => {
    allowed(`cd ${q(WT)} && git commit -m x`, MAIN);
    allowed(`git -C '${WT}' commit -m x`, MAIN);
    blocked(`git -C '${MAIN}' commit -m x`, WT);
  });
  test('paths containing a space', () => {
    allowed(`cd ${q(WT_SPACE)} && git commit -m x`, MAIN);
    allowed(`git -C '${WT_SPACE}' commit -m x`, MAIN);
    allowed(`cd ${WT_SPACE.replace(/ /g, '\\ ')} && git commit -m x`, MAIN);
    allowed('cd ~/dev/"proj wt" && git commit -m x', MAIN);
    allowed('git -C "proj wt" commit -m x', path.join(HOME, 'dev'));
    blocked(`cd ${q(MAIN)} && git commit -m x`, WT_SPACE);
  });
  test('quoted tilde is literal (shell does not expand it)', () => {
    // "~/dev/..." is not expanded by the shell; the cd target is a
    // non-existent relative dir under the worktree, so it is judged there.
    allowed('git -C "~/dev/proj" commit -m x', WT);
  });
});

describe('text that only looks like git is ignored', () => {
  test('commit message here-doc with tricky content (worktree) → allow', () => {
    const cmd = [
      `cd ${WT} && git commit -m "$(cat <<'EOF'`,
      `fix: don't break (edge case`,
      `git push -f origin main; git commit -m "nope"`,
      `it's fine && done`,
      'EOF',
      ')"',
    ].join('\n');
    allowed(cmd, MAIN);
  });
  test('same here-doc commit on main → block (exactly one commit seen)', () => {
    const cmd = `git commit -m "$(cat <<'EOF'\ntitle\n\nbody mentions git -C ${WT} commit\nEOF\n)"`;
    blocked(cmd, MAIN);
    const calls = bp.findGitCalls(cmd, MAIN).filter(c => c.sub);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].sub, 'commit');
    assert.equal(calls[0].dir, MAIN);
  });
  test('echo / grep / comments mentioning git commit → allow', () => {
    allowed('echo "git commit -m x"', MAIN);
    allowed('grep -rn "git push --force origin main" .', MAIN);
    allowed('ls # git commit -m x', MAIN);
    allowed("cat > notes.txt <<EOF\ngit commit -m x\nEOF", MAIN);
  });
});

describe('force push', () => {
  test('git push -f origin main → block', () => {
    blocked('git push -f origin main', WT);
  });
  test('git -C <worktree> push --force origin main → block', () => {
    blocked(`git -C ${WT} push --force origin main`, MAIN);
  });
  test('other force spellings → block', () => {
    blocked('git push origin main --force', WT);
    blocked('git push --force-with-lease origin main', WT);
    blocked('git push --force-with-lease=main:abc origin main', WT);
    blocked('git push -uf origin main', WT);
    blocked('git push origin +main', WT);
    blocked('git push -f origin feature/x:main', WT);
    blocked('git push -f origin HEAD:refs/heads/master', WT);
    blocked('git push --mirror origin', WT);
    blocked('git push -f --all origin', WT);
  });
  test('force push with implicit target follows the checked directory', () => {
    blocked('git push -f', MAIN);
    blocked('git push --force origin HEAD', MAIN);
    allowed('git push -f', WT);
    allowed('git push --force origin HEAD', WT);
    allowed(`git -C ${WT} push -f`, MAIN);
  });
  test('force push to a feature branch / normal push → allow', () => {
    allowed('git push --force origin feature/x', MAIN);
    allowed('git push -f origin feature/main-fix', MAIN);
    allowed('git push origin main', MAIN);
    allowed('git push -u origin feature/x', MAIN);
  });
});

describe('skip list', () => {
  test('commit on main inside a listed repo → allow', () => {
    allowed('git commit -m x', SOLO);
    allowed(`cd ${SOLO} && git commit -m x`, MAIN);
    allowed('git -C ~/dev/solo commit -m x', MAIN);
    allowed('git -C ~/dev/solo push -f origin main', MAIN);
  });
  test('subdirectory of a listed repo → allow', () => {
    fs.mkdirSync(path.join(SOLO, 'sub'), { recursive: true });
    allowed('git commit -m x', path.join(SOLO, 'sub'));
  });
  test('listed path only mentioned in text no longer skips a resolved call', () => {
    blocked(`git -C ${MAIN} commit -m "see ~/dev/solo"`, SOLO);
    blocked(`cd ~/dev/solo && git pull; cd ${MAIN} && git commit -m x`, WT);
  });
  test('unresolved directory still honours the legacy text rule', () => {
    allowed('cd "$SOME_REPO" && git commit -m x # ~/dev/solo', MAIN);
  });
});

describe('not guarded / warnings', () => {
  test('non-git commands, git status, git log → allow', () => {
    allowed('ls -la', MAIN);
    allowed('npm test', MAIN);
    allowed('git status', MAIN);
    allowed('git log --oneline -5', MAIN);
    allowed('git -C ~/dev/proj diff', WT);
    allowed('git commit -m x', PLAIN);
  });
  test('merge/rebase/reset on main → allowed with warning naming the dir', () => {
    const r = allowed('git merge feature/x', MAIN);
    assert.match(r.stderr, /WARNING: 'merge' on 'main'/);
    assert.ok(r.stderr.includes(MAIN));
    assert.match(allowed('git reset --hard HEAD~1', MAIN).stderr, /WARNING/);
    assert.match(allowed('git checkout feature/x', MAIN).stderr, /WARNING/);
  });
  test('same commands in the worktree → no warning', () => {
    assert.equal(allowed(`git -C ${WT} rebase main`, MAIN).stderr, '');
    assert.equal(allowed('git checkout -b feature/y', MAIN).stderr, '');
  });
});

describe('fallbacks', () => {
  test('dynamic cd target falls back to session cwd', () => {
    const r = blocked('cd "$WT_DIR" && git commit -m x', MAIN);
    assert.match(r.stderr, /could not resolve/);
    allowed('cd "$WT_DIR" && git commit -m x', WT);
    allowed(`cd "$(git rev-parse --show-toplevel)" && git commit -m x`, WT);
  });
  test('absolute -C after an unknown cd is still resolved', () => {
    allowed(`cd "$X" && git -C ${WT} commit -m x`, MAIN);
  });
  test('hook input without cwd → process.cwd()', () => {
    blocked('git commit -m x', null, { omitCwd: true, processCwd: MAIN });
    allowed('git commit -m x', null, { omitCwd: true, processCwd: WT });
    allowed(`cd ${WT} && git commit -m x`, null, { omitCwd: true, processCwd: MAIN });
  });
  test('legacy evaluator (used if the parser throws) judges the session cwd', () => {
    const realHome = process.env.HOME;
    process.env.HOME = HOME; // legacyEvaluate expands ~ from HOME
    try {
      assert.ok(bp.legacyEvaluate('git commit -m x', MAIN, []).block);
      assert.equal(bp.legacyEvaluate('git commit -m x', WT, []).block, null);
      assert.equal(bp.legacyEvaluate('git commit -m x', SOLO, [SOLO]).block, null);
    } finally {
      process.env.HOME = realHome;
    }
  });
  test('malformed / unterminated input does not crash the hook', () => {
    allowed(`git -C ${WT} commit -m "unterminated`, MAIN);
    allowed("echo 'unterminated", MAIN);
    allowed('echo $(( 1 + (2 ', MAIN);
    allowed('git status <<EOF', MAIN);
    const g = spawnSync(process.execPath, [HOOK], { input: '{oops', encoding: 'utf8', env: cleanEnv(), cwd: TMP });
    assert.equal(g.status, 0);
    assert.equal(g.stdout, '{oops');
  });
});
