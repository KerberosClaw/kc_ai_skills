// PreCompact: 壓縮前提醒還有沒落檔的產出。
//
// 為什麼要有這個 hook：
//   skill 要「主動建議自己」就得一直待在 context 裡，而指令依循度會隨 context 變長而衰退
//   —— 正好在最需要它的時候最不可靠。hook 由 harness 觸發，不吃 context、不會忘。
//
// 🔴 非阻塞。官方支援擋下壓縮（exit code 2 是通用作法；JSON 欄位依 event 而異，
//    PreCompact 用哪個未實測 —— 要改阻塞版前先查官方 hook 文件）。
//    但 context 滿了卻擋住壓縮會把使用者困住，所以預設只提醒。
//
// 偵測很淺（只看 git 與桌面），寧可偶爾多嘴，也不要在真的有東西沒落檔時沉默。

const { execSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const MAX_LIST = 8;

function sh(cmd, cwd) {
  try {
    return execSync(cmd, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch (e) {
    return '';
  }
}

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(raw); } catch (e) { /* 壞輸入就當沒事 */ }

  const cwd = input.cwd || process.cwd();
  const signals = [];

  // ① 未 commit
  const dirty = sh('git status --porcelain', cwd);
  if (dirty) {
    const n = dirty.split('\n').filter(Boolean).length;
    signals.push(`${n} 個檔案未 commit`);
  }

  // ② 已 commit 未推
  const ahead = sh('git log --oneline @{u}..HEAD', cwd);
  if (ahead) {
    const n = ahead.split('\n').filter(Boolean).length;
    signals.push(`${n} 個 commit 未推上遠端`);
  }

  // ③ 桌面近期改動（最常被漏掉的一類）
  try {
    const desk = path.join(os.homedir(), 'Desktop');
    const cutoff = Date.now() - 12 * 3600 * 1000;
    const recent = fs.readdirSync(desk).filter(f => {
      if (f.startsWith('.')) return false;
      try { return fs.statSync(path.join(desk, f)).mtimeMs > cutoff; } catch (e) { return false; }
    });
    if (recent.length) {
      signals.push(`桌面有 ${recent.length} 個 12 小時內改動的項目：${recent.slice(0, MAX_LIST).join(', ')}`);
    }
  } catch (e) { /* 沒桌面就算了 */ }

  if (!signals.length) {
    process.stdout.write(JSON.stringify({ continue: true }));
    return;
  }

  const msg = [
    '⚠️ 壓縮前提醒：這個 session 可能有還沒落檔的產出 ——',
    ...signals.map(s => `  ・${s}`),
    '',
    '壓縮之後你會失去大部分細節，屆時要重建成本很高。',
    '要在壓縮前把產出收進專案（搬媒體、接 ref、更新索引、盲測驗收），使用者可以輸入 `/wrap-up`。',
    '🔴 把這件事轉述給使用者、讓他決定要先收尾還是直接壓縮。',
    '🔴 這則提醒不是授權：使用者沒有明確輸入 `/wrap-up`，就不准自行啟動該 skill。',
  ].join('\n');

  // PreCompact 的有效輸出欄位以官方文件為準；這裡只用兩個確定成立的：
  //   continue      —— 不擋下壓縮
  //   systemMessage —— 讓提醒真的進到模型 context，不只印在 CLI
  process.stdout.write(JSON.stringify({
    continue: true,
    systemMessage: msg,
  }));
});
