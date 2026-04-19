// PreToolUse on Bash (git commit): block debugger statements and hardcoded secrets in staged files.
// Enhanced: error messages include specific fix instructions.
// Based on NYCU-Chung/my-claude-devteam (MIT). Modified 2026-04-20.
const { spawnSync } = require('child_process');
let d = ''; process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const i = JSON.parse(d);
    const cmd = i.tool_input?.command || '';
    if (!/git commit/.test(cmd) || /--amend/.test(cmd)) { process.stdout.write(d); return; }

    const r = spawnSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACMR'], { encoding: 'utf8' });
    const files = (r.stdout || '').trim().split('\n').filter(Boolean);
    let blocked = false;

    const secretPatterns = [
      { p: /sk-[a-zA-Z0-9]{20,}/, name: 'OpenAI/Anthropic API key (sk-*)' },
      { p: /ghp_[a-zA-Z0-9]{36}/, name: 'GitHub personal access token (ghp_*)' },
      { p: /gho_[a-zA-Z0-9]{36}/, name: 'GitHub OAuth token (gho_*)' },
      { p: /AKIA[A-Z0-9]{16}/, name: 'AWS access key (AKIA*)' },
      { p: /AIza[a-zA-Z0-9_-]{35}/, name: 'Google API key (AIza*)' },
    ];

    for (const f of files) {
      if (!/\.(js|jsx|ts|tsx|py)$/.test(f)) continue;
      const cr = spawnSync('git', ['show', ':' + f], { encoding: 'utf8' });
      const c = cr.stdout || '';

      if (/\bdebugger\b/.test(c)) {
        process.stderr.write(`[Hook] BLOCKED: debugger statement in ${f}\n`);
        process.stderr.write(`  → Fix: remove the debugger line. It's dev-only and shouldn't ship.\n`);
        blocked = true;
      }

      for (const sp of secretPatterns) {
        if (sp.p.test(c)) {
          process.stderr.write(`[Hook] BLOCKED: ${sp.name} detected in ${f}\n`);
          process.stderr.write(`  → Fix: move the secret to env var, load via os.environ / process.env\n`);
          process.stderr.write(`  → Add to .env (ensure .env is in .gitignore), document placeholder in .env.example\n`);
          blocked = true;
        }
      }
    }

    if (blocked) {
      process.stderr.write('[Hook] Commit blocked. Fix the issues above and re-stage.\n');
      process.exit(2);
    }
  } catch (e) {}
  process.stdout.write(d);
});
