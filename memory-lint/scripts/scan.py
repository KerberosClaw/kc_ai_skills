#!/usr/bin/env python3
"""memory-lint 機械掃描：只用標準函式庫，不動任何檔案。

用法: python3 scan.py <memory_dir>

刻意的設計：
- 目標目錄一律由參數帶入，不依賴呼叫端的工作目錄
- 不用 shell glob（zsh 未匹配會中止整條指令）
- 不用固定路徑的暫存檔（並行執行會互相覆蓋）
- 不 import 第三方套件（唯讀階段不該動使用者的 Python 環境）
"""
import os, re, sys, json, urllib.parse

ROOT_SKIP = re.compile(r"^(MEMORY|index_)")
LINK = re.compile(r"\]\(\s*<?([^)>]+\.md)>?\s*\)")   # 同時吃 (a.md)、(<a b.md>)、(a%20b.md)
WIKI = re.compile(r"\[\[([^\]]+)\]\]")
FENCED = re.compile(r"^```.*?^```", re.S | re.M)
INLINE = re.compile(r"`[^`\n]*`")


def norm(p):
    """正規化 markdown 連結目標：去掉 <>、URL 解碼、去掉 ./ 前綴。

    含空格的檔名在 markdown 裡會寫成 my%20note.md 或 <my note.md>，
    不還原的話同一個檔會同時被報成 orphan 與 missing，兩個都是假的。
    """
    p = p.strip()
    if p.startswith("<") and p.endswith(">"):
        p = p[1:-1]
    p = urllib.parse.unquote(p)
    return p[2:] if p.startswith("./") else p


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def frontmatter(text):
    """回傳 (ok, 頂層欄位 dict, metadata 子欄位 dict)。不用 YAML 解析器。"""
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return False, {}, {}
    top, meta, in_meta = {}, {}, False
    for line in m.group(1).split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indented = line[:1] in (" ", "\t")
        kv = re.match(r"^\s*([A-Za-z_][\w-]*)\s*:\s*(.*)$", line)
        if not kv:
            continue
        k, v = kv.group(1), kv.group(2).strip().strip('"').strip("'")
        if not indented:
            in_meta = (k == "metadata")
            top[k] = v
        elif in_meta:
            meta[k] = v
    return True, top, meta


def main(mem):
    if not os.path.isfile(os.path.join(mem, "MEMORY.md")):
        print(json.dumps({"fatal": "缺 MEMORY.md，視為無效路徑"}, ensure_ascii=False))
        return 1

    root = sorted(f for f in os.listdir(mem)
                  if f.endswith(".md") and os.path.isfile(os.path.join(mem, f)))
    payload = [f for f in root if not ROOT_SKIP.match(f)]          # 一般記憶檔
    on_disk_idx = [f for f in root if f.startswith("index_")]

    memtext = read(os.path.join(mem, "MEMORY.md"))
    root_links = {norm(x) for x in LINK.findall(memtext)}
    declared_idx = {x for x in root_links if x.startswith("index_")}
    reachable = sorted(declared_idx & set(on_disk_idx))
    two_tier = bool(reachable)

    indexed = {x for x in root_links if not x.startswith("index_")}
    for idx in reachable:
        indexed |= {norm(x) for x in LINK.findall(read(os.path.join(mem, idx)))
                    if not norm(x).startswith("index_")}

    out = {
        "memory_dir": mem,
        "layout": "兩層" if two_tier else "單層",
        "counts": {"root_md": len(root), "payload": len(payload),
                   "index_files": len(on_disk_idx), "reachable_index": len(reachable)},
        "index_declared_missing": sorted(declared_idx - set(on_disk_idx)),
        "index_orphaned": sorted(set(on_disk_idx) - declared_idx),
        "orphan": sorted(set(payload) - indexed),
        "missing": sorted(indexed - set(payload)),
    }

    # frontmatter：name/description 只認頂層；type 允許在 metadata 底下
    fm_bad, names = [], {}
    for f in payload + on_disk_idx:
        ok, top, meta = frontmatter(read(os.path.join(mem, f)))
        if not ok:
            fm_bad.append([f, "無 frontmatter"]); continue
        for k in ("name", "description"):
            if not top.get(k, "").strip():
                fm_bad.append([f, f"缺 {k}"])
        if not (top.get("type", "").strip() or meta.get("type", "").strip()):
            fm_bad.append([f, "缺 type"])
        if top.get("name", "").strip():
            names[top["name"].strip()] = f
    out["frontmatter"] = fm_bad

    # [[...]] 交叉連結：先剝程式碼；檔名與 frontmatter name 兩種都算解析成功
    stems = {f[:-3] for f in root}
    broken, ext = {}, {}
    for f in root:
        body = INLINE.sub("", FENCED.sub("", read(os.path.join(mem, f))))
        for ln, line in enumerate(body.split("\n"), 1):
            for t in WIKI.findall(line):
                t = t.strip()
                if t.endswith(".md"):
                    t = t[:-3]
                if t in stems or t in names:
                    continue
                (ext if "/" in t else broken).setdefault(t, set()).add(f"{f}:{ln}")
    out["wiki_broken"] = {k: sorted(v) for k, v in sorted(broken.items())}
    out["wiki_external"] = {k: sorted(v) for k, v in sorted(ext.items())}

    out["oversize"] = sorted(
        [f, read(os.path.join(mem, f)).count("\n")] for f in root
        if read(os.path.join(mem, f)).count("\n") > 300)

    pref = {}
    for f in payload:
        pref.setdefault(f.split("_")[0] + "_" if "_" in f else "(無前綴)", []).append(f)
    out["prefixes"] = {k: len(v) for k, v in sorted(pref.items(), key=lambda x: -len(x[1]))}
    out["no_prefix"] = sorted(pref.get("(無前綴)", []))

    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(2)
    sys.exit(main(os.path.abspath(os.path.expanduser(sys.argv[1]))))
