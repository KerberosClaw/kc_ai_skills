#!/usr/bin/env python3
"""驗收「編輯模式」的產出：codex 到底是就地修改，還是重新生成了一張很像的？

用法：
    verify_edit.py <底圖> <輸出圖> <bgremove|local>

    bgremove  去背。期待「主體一個像素都沒動」，只有背景變透明。
    local     局部修改。期待「改動聚在一塊，其餘沒動」。

退出碼：
    0  PASS
    1  FAIL（原因印在 stdout）
    2  用法錯誤 / 檔案讀不到 / 未知的 kind

為什麼需要這支：模型拿到編輯任務時，預設行為是「重新生成」不是「就地修改」。
重生出來的圖肉眼看起來幾乎一樣，但主體會位移幾十個像素 —— 那會讓這張圖跟
同批其他圖對不齊。人眼在表情或姿態有變化時分辨不出這種位移，所以要用量的。

🔴 兩種 kind 的判準**不一樣**，不要共用：
   去背要求逐像素不變（改了就是重生）；
   局部修改**本來就會有大色差**，硬套「色差要小」會讓它永遠不可能通過。
   分辨局部修改與重生，靠的是**改動像素的分布**：前者聚在一塊，後者滿版都在變。
"""
import sys

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow：python3 -m pip install pillow", file=sys.stderr)
    sys.exit(2)

KINDS = ("bgremove", "local")

LUMA_MARGIN = 60        # 「暗於背景這麼多」才算主體
DARK_BG_FLOOR = 60      # 背景亮度低於此值時，明度判準失效、改走 alpha
STEP = 2                # 取樣間隔
DIFF_HIT = 10           # 單點色差超過此值＝這個像素被改動了
BGREMOVE_MAX_DIFF = 9   # 去背時主體容許的最大色差
BGREMOVE_MAX_RATIO = 0.01
REGEN_RATIO = 0.90      # 主體有這麼高比例的像素都被改動＝整張重生，硬擋
SUSPICIOUS_RATIO = 0.25 # 超過此比例只印警告不擋 —— 「換掉整件衣服」與「主體位移」
                        # 在這個指標上長得一樣，硬擋會誤殺前者
MIN_CLEAR_RATIO = 0.01  # 宣稱去背時，透明像素至少要佔這麼多（低於此＝假去背）
MAX_CLEAR_RATIO = 0.98  # 高於此＝主體大概也被挖掉了，交出一張空圖
MAX_GHOST_RATIO = 0.05  # 半透明像素佔比上限。實測乾淨的去背是 0.0%～0.5%（邊緣抗鋸齒），
                        # 佔到 5% 以上就不是邊緣了，是整片主體變半透明。
                        # ⚠️ 這個門檻**沒有真實失敗案例驗證過**，是防呆不是實測值


def has_alpha(im):
    """mode P 的透明 PNG 也算 —— 只看 RGBA/LA 會漏掉，而漏掉的後果是把帶透明度的
    圖判成不帶，然後一路轉成 jpg 把透明度永久毀掉。"""
    return im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    src_path, out_path, kind = argv[1], argv[2], argv[3]

    if kind not in KINDS:
        # 刻意不預設成 local：預設會讓「忘了指定去背」靜默跳過透明度檢查，
        # 而那正是這支程式最該擋的失敗態。
        print(f"未知的 kind：{kind!r}，必須是 {' 或 '.join(KINDS)}", file=sys.stderr)
        return 2

    try:
        src, out = Image.open(src_path), Image.open(out_path)
    except Exception as e:
        print(f"讀不到圖：{e}", file=sys.stderr)
        return 2

    w, h = src.size
    fail = []

    # ① 畫布尺寸沒變
    if out.size != (w, h):
        fail.append(f"畫布跑掉：{out.size} != {(w, h)}")

    # ② 透明度 —— 只有 bgremove 要驗
    if kind == "bgremove":
        if not has_alpha(out):
            fail.append(f"要的是去背，但輸出沒有透明度（mode={out.mode}）")
        else:
            hist = out.convert("RGBA").getchannel("A").histogram()
            n = sum(hist)
            clear = hist[0] / n                      # 全透明＝被挖掉的背景
            solid = hist[255] / n                    # 全不透明＝實心的主體
            ghost = 1 - clear - solid                # 半透明＝鬼影
            print(f"透明像素 {clear:.1%}／實心 {solid:.1%}／半透明 {ghost:.1%}")

            if clear < MIN_CLEAR_RATIO:
                fail.append(f"幾乎沒有透明像素（{clear:.1%}）：可能是畫上去的假背景")
            if clear > MAX_CLEAR_RATIO:
                fail.append(f"透明像素高達 {clear:.1%}：主體八成也被一起挖掉了")

            # 🔴 鬼影：主體整片變成半透明。這條非查不可，因為第三項抓不到 ——
            #    半透明像素的 RGB 是完好的，「最大色差 0」照樣成立，圖卻是壞的。
            #    ⚠️ 尚未在真實輸出上遇過，屬防呆。但 codex 的 alpha 行為確實不穩定
            #    （同樣的 prompt 結構，實測一次吐純二值遮罩、一次吐邊緣羽化）。
            if ghost > MAX_GHOST_RATIO:
                fail.append(f"主體是半透明的鬼影（{ghost:.1%} 的像素落在 0 與 255 之間）"
                            "：背景是挖掉了，但主體沒有實心保留")

            # 刻意不驗「四角必須透明」——主體貼齊邊緣的構圖本來就有不透明的角。
            # 一個必過閘門只要常假失敗，就會被學會忽略。

    # ③ 主體像素保真（尺寸不同就沒得比，跳過）
    if out.size == (w, h):
        sp = src.convert("RGB").load()
        op = out.convert("RGB").load()
        ap = out.convert("RGBA").getchannel("A").load() if has_alpha(out) else None
        gp = src.convert("L").load()
        bg = gp[5, 5]
        use_luma = bg >= DARK_BG_FLOOR

        tot = worst = over = 0
        x0 = y0 = 10 ** 9
        x1 = y1 = -1
        for y in range(0, h, STEP):
            for x in range(0, w, STEP):
                if ap is not None:
                    if ap[x, y] == 0:
                        continue
                elif use_luma:
                    if gp[x, y] >= bg - LUMA_MARGIN:
                        continue
                d = max(abs(op[x, y][i] - sp[x, y][i]) for i in range(3))
                tot += 1
                worst = max(worst, d)
                if d > DIFF_HIT:
                    over += 1
                    x0, x1 = min(x0, x), max(x1, x)
                    y0, y1 = min(y0, y), max(y1, y)

        if tot == 0:
            fail.append("主體取樣為 0：背景判準失效（底圖是暗背景、或整張已透明）。"
                        "改用輸出的 alpha 當遮罩重跑，或請 user 目視比對")
        else:
            ratio = over / tot
            print(f"主體取樣 {tot}px  最大色差 {worst}  色差>{DIFF_HIT} 佔 {ratio:.1%}")

            if kind == "bgremove":
                # 去背不該動到主體任何一個像素
                if worst > BGREMOVE_MAX_DIFF or ratio > BGREMOVE_MAX_RATIO:
                    fail.append(f"去背卻動到主體（最大色差 {worst}、改動佔 {ratio:.1%}）"
                                "：它重新生成了一張像的，不是把背景挖掉")
            else:
                # 局部修改：改動本來就存在，要判的是「改動有沒有聚在一塊」
                if over == 0:
                    print("改動區域：無（輸出與底圖在主體上完全相同）")
                    fail.append("宣稱是局部修改，但主體沒有任何改動 —— "
                                "codex 可能沒照做，或改動落在被判為背景的區域")
                else:
                    bw, bh = x1 - x0 + STEP, y1 - y0 + STEP
                    print(f"改動區域：x {x0}–{x1}  y {y0}–{y1}"
                          f"（{bw}x{bh}，佔畫面 {bw * bh / (w * h):.1%}）")
                    if ratio > REGEN_RATIO:
                        fail.append(f"主體有 {ratio:.1%} 的像素都被改動 —— "
                                    "那不是局部修改，是整張重生")
                    elif ratio > SUSPICIOUS_RATIO:
                        # 硬擋只留無爭議的極端。這個中間地帶是真的判不出來：
                        # 「換掉整件衣服」跟「主體位移了幾十像素」在這裡長得一樣。
                        print(f"⚠️ 改動涵蓋主體的 {ratio:.1%}，範圍偏大。"
                              "如果你要求的只是一小處，這比較像重生而不是局部修改 —— 請目視確認")
                    else:
                        print("⚠️ 改動區域是否就是你要求的那一處，程式判不出來 —— "
                              "把上面那個座標框對照一下 prompt，或請 user 目視確認")

    print("VERDICT:", "PASS" if not fail else "FAIL")
    for f in fail:
        print(" -", f)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
