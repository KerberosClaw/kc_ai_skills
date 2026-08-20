# 結構檢查腳本

> 給 `wrap-up` Step 3c 用。**本 skill 自己做這些檢查，不呼叫 `llm-wiki-lint`** ——
> 它是報告型、有自己的核准閘門，且判準是結構性的：照它做完仍可能過不了盲測。
> 這裡借用的是它的**檢查項目**，不是它的執行。

## 一次跑完四類

存成 `/tmp/wrapup_lint.py` 再跑，不要塞進一行 shell（引號會被吃掉）。

```python
#!/usr/bin/env python3
"""wrap-up 結構檢查：斷連結／孤兒／過時路徑／索引落差。

用法：python3 wrapup_lint.py [repo路徑] [已刪除的路徑關鍵字...]
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

REPO = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
STALE = sys.argv[2:]                      # 例：Desktop/scratch_v1 old_exports
os.chdir(REPO)

mds = subprocess.run(["git", "ls-files", "*.md"],
                     capture_output=True, text=True).stdout.split()


def archived(p):
    """封存區的斷連結是低優先，分開算。"""
    return any(k in p for k in ("_archive", "deprecated", "/archive/"))


LINK = re.compile(r"\[[^\]]*\]\(([^)#\s]+)(?:#[^)]*)?\)")

broken_live, broken_arch = [], []
linked = set()
stale_hits = defaultdict(list)

for md in mds:
    try:
        s = open(md, errors="replace").read()
    except OSError:
        continue
    d = os.path.dirname(md)
    for m in LINK.finditer(s):
        t = m.group(1)
        if t.startswith(("http://", "https://", "mailto:")):
            continue
        p = os.path.normpath(os.path.join(d, t))
        if os.path.exists(p):
            linked.add(p)                 # 目錄也算被連到
        else:
            (broken_arch if archived(md) else broken_live).append((md, t))
    for kw in STALE:
        for m in re.finditer(re.escape(kw), s):
            ln = s[:m.start()].count("\n") + 1
            stale_hits[md].append((ln, s.split("\n")[ln - 1].strip()[:100]))

print(f"markdown {len(mds)} 份\n")
print(f"🔴 斷連結（現役）：{len(broken_live)}")
for md, t in broken_live:
    print(f"   {md} → {t}")
print(f"⚪ 斷連結（封存，低優先）：{len(broken_arch)}")

print(f"\n🔴 提到已刪除路徑：{sum(len(v) for v in stale_hits.values())} 處")
for md, rows in sorted(stale_hits.items()):
    print(f"   {md}（{len(rows)} 處）")
    for ln, txt in rows[:3]:
        print(f"      L{ln}: {txt}")

docs = [m for m in mds if not archived(m)]
orph = sorted(d for d in docs if d not in linked)
print(f"\n🟡 孤兒（沒有任何文件連到）：{len(orph)}")
for o in orph:
    print(f"   {o}")
```

## 判讀

| 類別 | 怎麼處理 |
|---|---|
| **斷連結（現役）** | 🔴 一定要修。多半是相對路徑層數算錯，或目標已搬走／已封存 |
| **斷連結（封存）** | ⚪ 不用管。封存區指向死檔案是正常的 |
| **提到已刪除路徑** | 🔴 **分兩種**：<br>① 敘述**現況**卻指向已刪的 → 必修<br>② **歷史紀錄**（log、舊 handoff 段）→ **保留原文、只加警語**，不要改寫歷史 |
| **孤兒** | 🟡 先確認是不是**以目錄被連到**（`docs/foo/` 被連 → 底下各章不算孤兒）。真孤兒才補進索引 |

## 常見誤判

- ❌ **把散文裡提到的檔名當斷連結** — `` `lessons_learned.md` `` 在反引號裡只是提及，不是連結。只檢查 `[x](y)` 形式
- ❌ **把目錄層連結算成孤兒** — 檢查器只看檔案層，會把被目錄連結涵蓋的子檔全部誤判
- ❌ **改寫 append-only 的 log** — log 是流水帳，過時就過時，加警語不改內容
