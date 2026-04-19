// PreToolUse on Bash: block/warn operations on protected branches.
// Protected: main, master, production, release, prod
// Enhanced: error messages include specific fix instructions.
// Per-repo opt-out: add repo path (one per line) to ~/.claude/branch-protection-skip.txt
// to disable this hook for that repo (useful for solo personal repos where
// direct-to-main is the norm). Supports ~ prefix for home dir.
// Based on NYCU-Chung/my-claude-devteam (MIT). Modified 2026-04-20.
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROTECTED = /^(main|master|production|release|prod)$/;

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

let d = '';
process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const i = JSON.parse(d);
    const cmd = String(i.tool_input?.command || '');
    if (!/\bgit\b/.test(cmd)) { process.stdout.write(d); return; }

    // Skip if command mentions any allowlisted repo path.
    // Matches both /abs/path/... and ~/... forms (HOME expanded).
    const skipList = loadSkipList();
    const cmdExpanded = cmd.replace(/~(?=[/\s])/g, os.homedir());
    for (const skipPath of skipList) {
      if (cmdExpanded.includes(skipPath)) { process.stdout.write(d); return; }
    }

    let branch = '';
    try {
      const r = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8', timeout: 5000 });
      branch = (r.stdout || '').trim();
    } catch (e) {}

    const onProtected = PROTECTED.test(branch);

    if (/git\s+push.*(--force|--force-with-lease|-f\b).*(main|master|production|release|prod)/.test(cmd)) {
      process.stderr.write(`[Hook] BLOCKED: Force push to a protected branch.\n`);
      process.stderr.write(`  → This overwrites upstream history — dangerous on shared branches.\n`);
      process.stderr.write(`  → To revert bad commits: use \`git revert <sha>\` (creates a new commit) instead of reset+force-push.\n`);
      process.exit(2);
    }

    if (onProtected && /git\s+commit\b/.test(cmd) && !/--amend.*--no-edit/.test(cmd)) {
      process.stderr.write(`[Hook] BLOCKED: You are on '${branch}' (protected).\n`);
      process.stderr.write(`  → Create a feature branch first:\n`);
      process.stderr.write(`       git checkout -b feature/<short-name>\n`);
      process.stderr.write(`  → Then commit and open PR against ${branch}.\n`);
      process.exit(2);
    }

    if (onProtected && /git\s+(merge|rebase|reset|cherry-pick|revert|checkout\s+[^-])/.test(cmd)) {
      process.stderr.write(`[Hook] WARNING: You are on '${branch}' (protected). Make sure this is intended.\n`);
    }
  } catch (e) {}
  process.stdout.write(d);
});
