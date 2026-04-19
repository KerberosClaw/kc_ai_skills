// PreToolUse on Read: warn at 500KB, block at 2MB.
// Enhanced: error messages include specific fix options.
// Based on NYCU-Chung/my-claude-devteam (MIT). Modified 2026-04-20.
const fs = require('fs');

const WARN_BYTES = 500 * 1024;
const BLOCK_BYTES = 2 * 1024 * 1024;

let d = '';
process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const i = JSON.parse(d);
    const fp = i.tool_input?.file_path;
    if (!fp) { process.stdout.write(d); return; }

    if (i.tool_input?.offset != null || i.tool_input?.limit != null) {
      process.stdout.write(d);
      return;
    }

    let stat;
    try { stat = fs.statSync(fp); } catch (e) { process.stdout.write(d); return; }
    if (!stat.isFile()) { process.stdout.write(d); return; }

    const size = stat.size;
    if (size >= BLOCK_BYTES) {
      process.stderr.write(
        `[Hook] BLOCKED: ${fp} is ${(size / 1024 / 1024).toFixed(1)} MB.\n` +
        `  → Reading the whole file would burn context. Options:\n` +
        `    (1) Read with offset/limit: Read(file_path=..., offset=N, limit=M)\n` +
        `    (2) Grep first to find the relevant section: Grep(pattern=..., path=...)\n` +
        `    (3) If it's a log: use Bash(tail -n 200 ${fp}) for recent entries\n`
      );
      process.exit(2);
    }
    if (size >= WARN_BYTES) {
      process.stderr.write(
        `[Hook] WARNING: ${fp} is ${(size / 1024).toFixed(0)} KB.\n` +
        `  → Consider offset/limit if you only need a portion, or Grep to find the specific section.\n`
      );
    }
  } catch (e) {}
  process.stdout.write(d);
});
