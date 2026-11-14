// PreToolUse on Bash: block/warn operations on protected branches.
// Protected: main, master, production, release, prod
// Enhanced: error messages include specific fix instructions.
//
// Which directory gets checked: the hook parses the command instead of asking
// git in the hook's own process directory. It starts from the session cwd in
// the hook input (`cwd`, falling back to process.cwd()), follows `cd`, `pushd`,
// `popd` and `( subshells )` across `&&`, `||`, `;`, `|`, `&` and newlines, and
// for every git invocation applies its global options (`-C <path>`, repeatable
// and relative to the previous one; `--git-dir`, `--work-tree`; `GIT_DIR=` /
// `GIT_WORK_TREE=` prefixes; `-c k=v`, `--no-pager`, ...). Branch and toplevel
// are then read with `git -C <dir> rev-parse` in that directory. Here-doc
// bodies, quoted strings and comments are never mistaken for commands.
// When a directory can't be known statically (e.g. `cd "$VAR"`), that git
// call falls back to the session cwd, which is what the hook used to do.
//
// Rules, per git invocation:
//   - force push whose target is a protected branch → BLOCK (explicit refspec,
//     `+refspec`, `HEAD` or no refspec while on a protected branch, --all,
//     --mirror)
//   - `git commit` on a protected branch → BLOCK (`--amend --no-edit` allowed)
//   - merge / rebase / reset / cherry-pick / revert / checkout <x> on a
//     protected branch → WARN only
//
// Per-repo opt-out: add repo path (one per line) to ~/.claude/branch-protection-skip.txt
// to disable this hook for that repo (useful for solo personal repos where
// direct-to-main is the norm). Supports ~ prefix for home dir. A git call is
// skipped when its directory, that directory's git toplevel, or its
// --git-dir / --work-tree lies inside a listed path. The legacy rule "command
// text mentions a listed path" now only applies to calls whose directory
// could not be resolved.
//
// If the parser throws, the hook falls back to the original regex checks
// evaluated in the session cwd; any other internal error lets the command
// through unchanged (stdin is echoed back to stdout).
//
// Tests: node --test hooks/branch-protection.test.mjs
// Based on NYCU-Chung/my-claude-devteam (MIT). Modified 2026-04-20, 2026-11-14.
'use strict';
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROTECTED = /^(main|master|production|release|prod)$/;
const PROTECTED_IN_TEXT = /\b(main|master|production|release|prod)\b/;
// Subcommands this hook cares about; anything else never spawns git.
const GUARDED = new Set(['commit', 'push', 'merge', 'rebase', 'reset', 'cherry-pick', 'revert', 'checkout']);
const WARN_ONLY = new Set(['merge', 'rebase', 'reset', 'cherry-pick', 'revert']);
// git global options that take their value as the next word.
const GIT_OPTS_WITH_ARG = new Set(['-c', '--namespace', '--config-env', '--super-prefix', '--attr-source', '--list-cmds']);
// git push options that take their value as the next word.
const PUSH_OPTS_WITH_ARG = new Set(['--repo', '--push-option', '--receive-pack', '--exec']);
const KEYWORDS = new Set(['if', 'then', 'else', 'elif', 'do', 'while', 'until', '!', '{', '}']);
const WRAPPERS = new Set(['env', 'command', 'builtin', 'exec', 'nohup', 'time', 'noglob', 'nocorrect']);
const SHELLS = new Set(['sh', 'bash', 'zsh', 'dash', 'ksh']);
const GIT_TIMEOUT_MS = 2000;

function loadSkipList() {
  try {
    const f = path.join(os.homedir(), '.claude', 'branch-protection-skip.txt');
    if (!fs.existsSync(f)) return [];
    return fs.readFileSync(f, 'utf8').split('\n')
      .map(l => l.trim())
      .filter(l => l && !l.startsWith('#'))
      .map(l => l.replace(/^~/, os.homedir()));
  } catch (e) { return []; }
}

// ---------------------------------------------------------------------------
// Shell lexer. Produces words and control operators. Handles quotes, escapes,
// comments, $(...), `...`, ${...}, here-docs (bodies skipped) and
// redirections (targets dropped). Never throws on malformed input: an
// unterminated construct simply runs to the end of the string.
// Each word: { value, raw, dynamic, glob, quoted, subs }
//   dynamic = contains an expansion we can't evaluate ($VAR, $(...), `...`)
//   subs    = token lists of command substitutions inside the word
// ---------------------------------------------------------------------------
function isMeta(c) {
  return c === ' ' || c === '\t' || c === '\r' || c === '\n' || c === ';' || c === '&'
    || c === '|' || c === '(' || c === ')' || c === '<' || c === '>';
}

function newWord() {
  return { value: '', raw: '', dynamic: false, glob: false, quoted: false, subs: [] };
}

const REDIRECT = /&>>|&>|>>|>&|>\||<&|<>|>|</y;

function lex(s, i = 0, closer = null) {
  const tokens = [];
  const heredocs = [];
  let depth = 0;
  let lastWordEnd = -1;
  const op = (o) => tokens.push({ type: 'op', op: o });
  while (i < s.length) {
    const c = s[i];
    const n = s[i + 1];
    if (c === ' ' || c === '\t' || c === '\r') { i++; continue; }
    if (c === '\\' && n === '\n') { i += 2; continue; }
    if (c === '\n') {
      op('\n'); i++;
      for (const h of heredocs.splice(0)) i = skipHeredoc(s, i, h);
      continue;
    }
    if (c === '#') { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (c === ')') {
      if (closer === ')' && depth === 0) return { tokens, pos: i + 1 };
      if (depth > 0) depth--;
      op(')'); i++; continue;
    }
    if (c === '(') { depth++; op('('); i++; continue; }
    if (c === ';') { op(';'); i += n === ';' ? 2 : 1; continue; }
    if (c === '&' && n === '&') { op('&&'); i += 2; continue; }
    if (c === '|' && n === '|') { op('||'); i += 2; continue; }
    if (c === '|') { op('|'); i += n === '&' ? 2 : 1; continue; }
    if (c === '&' && n !== '>') { op('&'); i++; continue; }
    if ((c === '<' || c === '>') && n === '(') {
      // process substitution <(...) / >(...)
      const w = newWord();
      const r = lex(s, i + 2, ')');
      w.dynamic = true; w.subs.push(r.tokens); w.raw = w.value = s.slice(i, r.pos);
      tokens.push({ type: 'word', ...w });
      i = lastWordEnd = r.pos;
      continue;
    }
    if (c === '<' || c === '>' || c === '&') {
      // Redirection. A digit word glued to it (`2>`) is its fd, not an argument.
      const prev = tokens[tokens.length - 1];
      if (prev && prev.type === 'word' && lastWordEnd === i && /^\d+$/.test(prev.raw)) tokens.pop();
      if (s.startsWith('<<<', i)) { i = skipWordAt(s, i + 3); continue; }
      if (s.startsWith('<<', i)) {
        i += 2;
        let strip = false;
        if (s[i] === '-') { strip = true; i++; }
        while (s[i] === ' ' || s[i] === '\t') i++;
        const r = readWord(s, i);
        heredocs.push({ delim: r.word.value, strip });
        i = r.pos;
        continue;
      }
      REDIRECT.lastIndex = i;
      const m = REDIRECT.exec(s);
      i = skipWordAt(s, i + (m ? m[0].length : 1));
      continue;
    }
    const r = readWord(s, i);
    tokens.push({ type: 'word', ...r.word });
    i = lastWordEnd = r.pos;
  }
  return { tokens, pos: i };
}

function skipWordAt(s, i) {
  while (s[i] === ' ' || s[i] === '\t') i++;
  if (i >= s.length || isMeta(s[i])) return i;
  return readWord(s, i).pos;
}

function skipHeredoc(s, i, h) {
  while (i < s.length) {
    let nl = s.indexOf('\n', i);
    if (nl < 0) nl = s.length;
    const raw = s.slice(i, nl);
    const line = h.strip ? raw.replace(/^\t+/, '') : raw;
    if (line === h.delim) return nl + 1;
    // `EOF)` closing a $( ... ) on the delimiter line
    if (h.delim && line.startsWith(h.delim + ')')) return i + (raw.length - line.length) + h.delim.length;
    i = nl + 1;
  }
  return s.length;
}

function readWord(s, i) {
  const w = newWord();
  const start = i;
  while (i < s.length && !isMeta(s[i])) {
    const c = s[i];
    if (c === '\\') {
      if (s[i + 1] !== '\n') { w.value += s[i + 1] || ''; w.quoted = true; }
      i += 2; continue;
    }
    if (c === "'") {
      w.quoted = true;
      const j = s.indexOf("'", i + 1);
      const e = j < 0 ? s.length : j;
      w.value += s.slice(i + 1, e);
      i = e + 1; continue;
    }
    if (c === '"') { w.quoted = true; i = readDouble(s, i + 1, w); continue; }
    if (c === '$') { i = readDollar(s, i, w); continue; }
    if (c === '`') { i = readBacktick(s, i, w); continue; }
    if (c === '~' && i === start && (i + 1 >= s.length || s[i + 1] === '/' || isMeta(s[i + 1]))) {
      w.value += os.homedir(); i++; continue;
    }
    if (c === '*' || c === '?' || c === '[') w.glob = true;
    w.value += c; i++;
  }
  w.raw = s.slice(start, i);
  return { word: w, pos: i };
}

function readDouble(s, i, w) {
  while (i < s.length) {
    const c = s[i];
    if (c === '"') return i + 1;
    if (c === '\\') {
      const n = s[i + 1];
      if (n === '\n') { i += 2; continue; }
      if (n === '$' || n === '`' || n === '"' || n === '\\') { w.value += n; i += 2; continue; }
      w.value += c; i++; continue;
    }
    if (c === '$') { i = readDollar(s, i, w); continue; }
    if (c === '`') { i = readBacktick(s, i, w); continue; }
    w.value += c; i++;
  }
  return i;
}

const VAR_NAME = /[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-]/y;

function readDollar(s, i, w) {
  const n = s[i + 1];
  if (n === '(') {
    w.dynamic = true;
    if (s[i + 2] === '(') { // $(( arithmetic ))
      let d = 0, j = i + 1;
      for (; j < s.length; j++) {
        if (s[j] === '(') d++;
        else if (s[j] === ')' && --d === 0) break;
      }
      w.value += s.slice(i, j + 1);
      return j + 1;
    }
    const r = lex(s, i + 2, ')');
    w.subs.push(r.tokens);
    w.value += s.slice(i, r.pos);
    return r.pos;
  }
  if (n === '{') {
    let j = s.indexOf('}', i + 2);
    if (j < 0) j = s.length;
    if (s.slice(i + 2, j) === 'HOME') w.value += os.homedir();
    else { w.dynamic = true; w.value += s.slice(i, j + 1); }
    return j + 1;
  }
  if (n === "'") { // $'...'
    let j = i + 2;
    while (j < s.length && s[j] !== "'") j += s[j] === '\\' ? 2 : 1;
    w.quoted = true;
    w.value += s.slice(i + 2, Math.min(j, s.length));
    return j + 1;
  }
  VAR_NAME.lastIndex = i + 1;
  const m = VAR_NAME.exec(s);
  if (m) {
    if (m[0] === 'HOME') w.value += os.homedir();
    else { w.dynamic = true; w.value += '$' + m[0]; }
    return i + 1 + m[0].length;
  }
  w.value += '$';
  return i + 1;
}

function readBacktick(s, i, w) {
  let j = i + 1, inner = '';
  while (j < s.length && s[j] !== '`') {
    if (s[j] === '\\' && j + 1 < s.length) { inner += s[j + 1]; j += 2; }
    else { inner += s[j]; j++; }
  }
  w.dynamic = true;
  w.subs.push(lex(inner).tokens);
  w.value += s.slice(i, j + 1);
  return j + 1;
}

// ---------------------------------------------------------------------------
// Walk the tokens, tracking the directory each command runs in, and collect
// git invocations. state.dir === null means "unknown" (dynamic cd target).
// ---------------------------------------------------------------------------
function findGitCalls(command, cwd) {
  const state = { dir: cwd, oldDir: null, pushStack: [], subshells: [] };
  const calls = [];
  walk(lex(command).tokens, state, calls);
  return calls;
}

function forkState(state) {
  return { dir: state.dir, oldDir: state.oldDir, pushStack: state.pushStack.slice(), subshells: [] };
}

function walk(tokens, state, calls) {
  let words = [];
  const flush = () => { if (words.length) simpleCommand(words, state, calls); words = []; };
  for (const t of tokens) {
    if (t.type === 'word') { words.push(t); continue; }
    flush();
    if (t.op === '(') {
      state.subshells.push({ dir: state.dir, oldDir: state.oldDir, pushStack: state.pushStack.slice() });
    } else if (t.op === ')') {
      const saved = state.subshells.pop();
      if (saved) Object.assign(state, saved);
    }
  }
  flush();
}

// For `NAME=~/x` and `--opt=~/x`, where the lexer's word-start tilde rule
// doesn't apply (bash expands the former; git fails on the latter anyway).
function expandTilde(v) {
  return v === '~' || v.startsWith('~/') ? os.homedir() + v.slice(1) : v;
}

function resolveFrom(base, w) {
  if (!w || w.dynamic || w.glob) return null;
  const v = w.value;
  if (path.isAbsolute(v)) return path.resolve(v);
  if (base === null) return null;
  return path.resolve(base, v);
}

function simpleCommand(words, state, calls) {
  // $(...) inside arguments runs first, in a copy of the current state.
  for (const w of words) for (const sub of w.subs) walk(sub, forkState(state), calls);

  const env = {};
  let k = 0;
  while (k < words.length) {
    const w = words[k];
    if (!w.quoted && KEYWORDS.has(w.value)) { k++; continue; }
    const assign = /^([A-Za-z_][A-Za-z0-9_]*)=/.exec(w.raw);
    if (assign) {
      env[assign[1]] = { value: expandTilde(w.value.slice(assign[0].length)), dynamic: w.dynamic, glob: w.glob };
      k++; continue;
    }
    if (!w.quoted && WRAPPERS.has(w.value)) {
      k++;
      while (k < words.length && words[k].value.startsWith('-')) k++;
      continue;
    }
    break;
  }
  if (k >= words.length) return;

  const name = words[k].value;
  const args = words.slice(k + 1);
  const base = path.basename(name);

  if (name === 'cd' || name === 'pushd') return changeDir(name, args, state);
  if (name === 'popd') {
    if (state.pushStack.length) { state.oldDir = state.dir; state.dir = state.pushStack.pop(); }
    return;
  }
  if (name === 'eval') {
    walk(lex(args.map(a => a.value).join(' ')).tokens, state, calls);
    return;
  }
  if (SHELLS.has(base)) {
    for (let a = 0; a < args.length; a++) {
      const v = args[a].value;
      if (!args[a].quoted && /^-[A-Za-z]*c[A-Za-z]*$/.test(v)) {
        if (args[a + 1]) walk(lex(args[a + 1].value).tokens, forkState(state), calls);
        break;
      }
      if (!v.startsWith('-')) break; // running a script file
    }
    return;
  }
  if (base === 'git') calls.push(parseGit(args, state, env));
}

function changeDir(name, args, state) {
  let a = 0;
  while (a < args.length && !args[a].quoted && /^-[LPe@]+$/.test(args[a].value)) a++;
  if (args[a] && args[a].value === '--') a++;
  const target = args[a];
  let next;
  if (!target) next = name === 'cd' ? os.homedir() : null; // bare pushd swaps: unknown
  else if (target.value === '-' && !target.quoted) next = state.oldDir;
  else next = resolveFrom(state.dir, target);
  if (name === 'pushd') state.pushStack.push(state.dir);
  state.oldDir = state.dir;
  state.dir = next;
}

function parseGit(args, state, env) {
  let dir = state.dir;
  let gitDirW = env.GIT_DIR || null;
  let workTreeW = env.GIT_WORK_TREE || null;
  let k = 0;
  while (k < args.length) {
    const a = args[k], v = a.value;
    if (v === '-C') {
      const p = args[k + 1];
      if (p && !(p.value === '' && !p.dynamic)) dir = resolveFrom(dir, p);
      k += 2; continue;
    }
    if (v === '--git-dir') { gitDirW = args[k + 1] || null; k += 2; continue; }
    if (v === '--work-tree') { workTreeW = args[k + 1] || null; k += 2; continue; }
    if (v.startsWith('--git-dir=')) { gitDirW = { ...a, value: expandTilde(v.slice(10)) }; k++; continue; }
    if (v.startsWith('--work-tree=')) { workTreeW = { ...a, value: expandTilde(v.slice(12)) }; k++; continue; }
    if (GIT_OPTS_WITH_ARG.has(v)) { k += 2; continue; }
    if (v.startsWith('-')) { k++; continue; }
    break;
  }
  const subW = args[k];
  let unresolved = dir === null;
  const resolveOpt = (w) => {
    if (!w) return undefined;
    const r = resolveFrom(dir, w);
    if (r === null) unresolved = true;
    return r || undefined;
  };
  return {
    sub: subW && !subW.dynamic ? subW.value : null,
    args: args.slice(k + 1),
    dir,
    gitDir: resolveOpt(gitDirW),
    workTree: resolveOpt(workTreeW),
    unresolved,
  };
}

// ---------------------------------------------------------------------------
// Decisions
// ---------------------------------------------------------------------------
function runGit(args) {
  try {
    const r = spawnSync('git', args, { encoding: 'utf8', timeout: GIT_TIMEOUT_MS });
    return r.status === 0 ? (r.stdout || '').trim() : '';
  } catch (e) { return ''; }
}

function gitInfo(dir, gitDir, workTree, cache) {
  const key = [dir, gitDir || '', workTree || ''].join('\0');
  if (cache && cache.has(key)) return cache.get(key);
  const base = ['-C', dir];
  if (gitDir) base.push('--git-dir=' + gitDir);
  if (workTree) base.push('--work-tree=' + workTree);
  const info = {
    toplevel: runGit([...base, 'rev-parse', '--show-toplevel']),
    branch: runGit([...base, 'rev-parse', '--abbrev-ref', 'HEAD']),
  };
  if (cache) cache.set(key, info);
  return info;
}

function nearestExisting(p) {
  let d = p;
  while (!fs.existsSync(d)) {
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  return d;
}

function pathVariants(p) {
  const out = new Set([path.resolve(p)]);
  try { out.add(fs.realpathSync(p)); } catch (e) {}
  return [...out];
}

function makeSkipMatcher(skipList) {
  const entries = skipList.flatMap(pathVariants).filter(e => e !== path.sep);
  return (p) => {
    if (!p) return false;
    const cands = pathVariants(p);
    return entries.some(e => cands.some(c => c === e || c.startsWith(e + path.sep)));
  };
}

// Returns the protected branch a force push would overwrite, or null.
function forcedProtectedTarget(args, currentBranch) {
  let force = false, all = false;
  const positional = [];
  for (let k = 0; k < args.length; k++) {
    const a = args[k], v = a.value;
    if (v === '--') { positional.push(...args.slice(k + 1)); break; }
    if (v.startsWith('--')) {
      if (v === '--force' || v === '--force-with-lease' || v.startsWith('--force-with-lease=')) force = true;
      else if (v === '--mirror') { force = true; all = true; }
      else if (v === '--all' || v === '--branches') all = true;
      else if (PUSH_OPTS_WITH_ARG.has(v)) k++;
      continue;
    }
    if (v.length > 1 && v.startsWith('-')) {
      for (let j = 1; j < v.length; j++) {
        if (v[j] === 'f') force = true;
        if (v[j] === 'o') { if (j === v.length - 1) k++; break; } // -o <push-option>
      }
      continue;
    }
    positional.push(a);
  }
  const refspecs = positional.slice(1); // first positional is the remote
  if (force && all) return '(all branches)';
  if (!refspecs.length) return force && PROTECTED.test(currentBranch) ? currentBranch : null;
  for (const r of refspecs) {
    let v = r.value;
    const plus = v.startsWith('+');
    if (plus) v = v.slice(1);
    if (!force && !plus) continue;
    if (r.dynamic) {
      if (PROTECTED_IN_TEXT.test(r.raw)) return r.raw;
      continue;
    }
    const colon = v.indexOf(':');
    let dst = colon >= 0 ? v.slice(colon + 1) : v;
    if (!dst) dst = colon >= 0 ? v.slice(0, colon) : v;
    if (dst === 'HEAD' || dst === '@') dst = currentBranch;
    dst = dst.replace(/^refs\/heads\//, '');
    if (dst.includes('*') || PROTECTED.test(dst)) return dst;
  }
  return null;
}

function describeWhere(where) {
  let s = where.dir;
  if (where.gitDir) s += ` (--git-dir ${where.gitDir})`;
  if (where.workTree) s += ` (--work-tree ${where.workTree})`;
  return `${s}, branch '${where.branch || '(none)'}'`;
}

function whereLines(where) {
  let s = `  → Checked: ${describeWhere(where)}\n`;
  if (where.fallback) {
    s += `  → Note: could not resolve this git command's directory (dynamic path such as "$VAR");\n`;
    s += `    checked the session cwd instead. Use a literal path to be judged correctly.\n`;
  }
  return s;
}

function forcePushMessage(target, where) {
  return `[Hook] BLOCKED: Force push to a protected branch ('${target}').\n`
    + `  → This overwrites upstream history — dangerous on shared branches.\n`
    + `  → To revert bad commits: use \`git revert <sha>\` (creates a new commit) instead of reset+force-push.\n`
    + whereLines(where);
}

function commitMessage(where) {
  return `[Hook] BLOCKED: You are on '${where.branch}' (protected).\n`
    + whereLines(where)
    + `  → Create a feature branch first:\n`
    + `       git checkout -b feature/<short-name>\n`
    + `  → Then commit and open PR against ${where.branch}.\n`
    + `  → Meant to commit in a worktree? Run git there: \`cd <worktree> && git commit …\` or \`git -C <worktree> commit …\`.\n`;
}

function warnMessage(sub, where) {
  return `[Hook] WARNING: '${sub}' on '${where.branch}' (protected) in ${where.dir}. Make sure this is intended.\n`;
}

// Main decision: { block: string|null, warnings: string[] }
function evaluate(command, cwd, skipList) {
  const verdict = { block: null, warnings: [] };
  const inSkip = makeSkipMatcher(skipList);
  const cmdExpanded = command.replace(/~(?=[/\s])/g, os.homedir());
  const mentionsSkip = skipList.some(p => cmdExpanded.includes(p));
  const cache = new Map();

  for (const call of findGitCalls(command, cwd)) {
    if (!GUARDED.has(call.sub)) continue;
    const fallback = call.unresolved;
    if (fallback && mentionsSkip) continue; // legacy rule, only when we can't tell
    const dir = nearestExisting(fallback ? cwd : call.dir);
    const gitDir = fallback ? undefined : call.gitDir;
    const workTree = fallback ? undefined : call.workTree;
    const info = gitInfo(dir, gitDir, workTree, cache);
    if ([info.toplevel, dir, fallback ? null : call.dir, gitDir, workTree].some(inSkip)) continue;
    const where = { dir, gitDir, workTree, branch: info.branch, fallback };

    if (call.sub === 'push') {
      const target = forcedProtectedTarget(call.args, info.branch);
      if (target) { verdict.block = forcePushMessage(target, where); return verdict; }
      continue;
    }
    if (!PROTECTED.test(info.branch)) continue;
    if (call.sub === 'commit') {
      const has = (f) => call.args.some(a => a.value === f);
      if (!(has('--amend') && has('--no-edit'))) { verdict.block = commitMessage(where); return verdict; }
      continue;
    }
    if (WARN_ONLY.has(call.sub)
      || (call.sub === 'checkout' && call.args.length && !call.args[0].value.startsWith('-'))) {
      verdict.warnings.push(warnMessage(call.sub, where));
    }
  }
  return verdict;
}

// The pre-2026-11-14 regex checks, evaluated in the session cwd. Used only if
// the parser above throws, so a parser bug degrades to the old behaviour
// instead of letting everything through or blocking everything.
function legacyEvaluate(cmd, cwd, skipList) {
  const verdict = { block: null, warnings: [] };
  const cmdExpanded = cmd.replace(/~(?=[/\s])/g, os.homedir());
  if (skipList.some(p => cmdExpanded.includes(p))) return verdict;
  const info = gitInfo(cwd);
  if (makeSkipMatcher(skipList)(info.toplevel)) return verdict;
  const where = { dir: cwd, branch: info.branch, fallback: true };
  const onProtected = PROTECTED.test(info.branch);

  const m = /git\s+push.*(--force|--force-with-lease|-f\b).*(main|master|production|release|prod)/.exec(cmd);
  if (m) { verdict.block = forcePushMessage(m[2], where); return verdict; }
  if (onProtected && /git\s+commit\b/.test(cmd) && !/--amend.*--no-edit/.test(cmd)) {
    verdict.block = commitMessage(where); return verdict;
  }
  if (onProtected && /git\s+(merge|rebase|reset|cherry-pick|revert|checkout\s+[^-])/.test(cmd)) {
    verdict.warnings.push(warnMessage('(legacy match)', where));
  }
  return verdict;
}

function main() {
  let d = '';
  process.stdin.on('data', c => d += c);
  process.stdin.on('end', () => {
    try {
      const i = JSON.parse(d);
      const cmd = String(i.tool_input?.command || '');
      if (!/\bgit\b/.test(cmd)) { process.stdout.write(d); return; }
      const cwd = typeof i.cwd === 'string' && i.cwd ? path.resolve(i.cwd) : process.cwd();
      const skipList = loadSkipList();
      let verdict;
      try { verdict = evaluate(cmd, cwd, skipList); }
      catch (e) { verdict = legacyEvaluate(cmd, cwd, skipList); }
      for (const w of verdict.warnings) process.stderr.write(w);
      if (verdict.block) {
        process.stderr.write(verdict.block);
        process.exitCode = 2;
        return;
      }
    } catch (e) {}
    process.stdout.write(d);
  });
}

module.exports = { lex, findGitCalls, forcedProtectedTarget, evaluate, legacyEvaluate, loadSkipList };

if (require.main === module) main();
