// PostToolUse on Bash: audit log all commands with auto-redaction of secrets.
// Based on NYCU-Chung/my-claude-devteam (MIT). Copied verbatim 2026-04-20 (no enhancements needed — this is a background logger).
const fs = require('fs');
const os = require('os');
const path = require('path');
let d = ''; process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const i = JSON.parse(d);
    const cmd = String(i.tool_input?.command || '?')
      .replace(/\n/g, ' ')
      .replace(/--token[= ][^ ]*/g, '--token=<REDACTED>')
      .replace(/password[= ][^ ]*/gi, 'password=<REDACTED>')
      .replace(/\bghp_[A-Za-z0-9_]+\b/g, '<REDACTED>')
      .replace(/\bgho_[A-Za-z0-9_]+\b/g, '<REDACTED>')
      .replace(/sshpass\s+-p\s+'[^']*'/g, "sshpass -p '<REDACTED>'")
      .replace(/AIza[a-zA-Z0-9_-]{35}/g, '<REDACTED>');
    const logDir = path.join(os.homedir(), '.claude');
    fs.mkdirSync(logDir, { recursive: true });
    fs.appendFileSync(
      path.join(logDir, 'bash-commands.log'),
      `[${new Date().toISOString()}] ${cmd}\n`
    );
  } catch (e) {}
  process.stdout.write(d);
});
