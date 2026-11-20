# vimi — MZ-2500 用 vim 風エディタ

シャープ MZ-2500 の LSX-Dodgersを改造したバージョン(LSX-Dodgers-m25Mutant)で動く vim 風エディタ `VIMI.COM`(28KB)です。
Z80 アセンブラが本体で、同じ動作をする C 版(`core/`)をホストでのテストの基準(oracle)として持っています。

A vim-like editor for the Sharp MZ-2500 running LSX-Dodgers (CP/M-80). The Z80 build is pure assembly (28KB);
the C implementation in `core/` is kept as the reference that the assembly is tested against.

## 状態
- **動作確認はエミュレータ(mz2500-web-emulator の CLI)上のみ。実機では未確認です。**
  特にキー入力はキーボード割り込み(0038h)を自前で差し替えており、元の割り込み処理へはつないでいません。
- 対象 OS は MZ-2500 向けに改造した LSX-Dodgers です。ページ API(E0h〜E3h)や E5h EXEC がある版ではそれを使い、
  無い版では自動的に「メモリ方式」「スワップファイル方式」に切り替わります(MZ-2500 の旧 LSX での回帰テストは通っています)。
- 他機種(X1 など)の LSX では、画面・キー・ストアの部分(下の「構成」の機種依存部)を作り直す必要があります。

## 主な機能
- ノーマル / 挿入 / ビジュアル(文字・行・矩形)、オペレータ+モーション、テキストオブジェクト、カウント、`.` 繰り返し
- レジスタ a–z、マーク、マクロ(`q` / `@`)、undo / redo
- 正規表現の検索(`/ ? n N * #`)、`:s` `:g` `:v`、行範囲
- `:e :w :q :r :!`(`:!cmd` は LSX の E5h、無い OS では VIMICMD.BAT 経由)
- 大きなファイル: ページ方式で約46KB、`-sF120` のようにスワップファイルを使うと最大約1MB(位置は32bit)
- テキスト面のハードウェアスクロール、`:set nu`
- 使い方の練習用チュートリアル: [`docs/TUTOR.TXT`](docs/TUTOR.TXT)

```
VIMI [-n] [-sD[KB]] [+N] [file]
  -n       OS のパレットを変えない
  -sF120   F: に 120KB のスワップファイル(大きいファイル用)
  +N       N 行目から開く
```

## ビルド済みバイナリ
[`dist/VIMI.COM`](dist/VIMI.COM)(このソースから作ったもの)。LSX のディスクに置いて実行します。

## ビルド
必要なもの: [z88dk](https://github.com/z88dk/z88dk)(sccz80 / z80asm)、bash、gcc(ホストテスト用)、python3。

    export Z88DK_PATH=/path/to/z88dk
    export ZCCCFG=$Z88DK_PATH/lib/config
    export PATH=$Z88DK_PATH/bin:$PATH
    bash tools/bz_build.sh          # → /tmp/v/VIMI.COM  (OUT=ディレクトリ で出力先を変更)

ビルドは「本体が A000h 未満に収まること」「スタックの余裕が 256 バイト以上あること」を確認し、足りなければ失敗します。

## テスト
ホストテスト(C 版の基準実装、AddressSanitizer / UBSan 付き):

    gcc -std=c99 -DTX_NBMAX=400 -DMZV_POS32 -DHOST_CAP=400000u -fsanitize=address,undefined -Icore \
        tests/test_core.c core/editor.c core/text_blk.c hal/hal_host.c hal/fs_host.c hal/store_host.c -o /tmp/tb && /tmp/tb

エミュレータでの突き合わせ(同じキー列を C 版と Z80 版に与えて、保存結果のバイト一致と画面を比べる)や
乱数キー列のテストは `tools/check.sh` にまとまっています(約45分。エミュレータと LSX のディスクが別途必要で、
パスは `tools/emu_regress.py` の先頭と `tools/check.sh` に `/home/claude/...` で固定されています。環境に合わせて書き換えてください)。ROM・LSX・エミュレータはこのリポジトリには含めていません。

## 構成
| ディレクトリ | 内容 |
|---|---|
| `core/` | 基準実装(C)。画面・キー・ストア・ファイルは `hal.h` `store.h` `fs.h` の3つの境界の向こう側 |
| `hal/` | Z80 アセンブラ(`*_z80.asm` が編集機能、`kbd_isr.asm` `vram_row.asm` `pal.asm` `sys_z80.asm` などが機種・OS 依存部)とホスト用 HAL |
| `z80/` | Z80 版の起動部 |
| `tests/` | ホストテスト |
| `tools/` | ビルド、ディスク作成、エミュレータ回帰・fuzz、キー表の生成、シナリオ(`tools/scen/`) |
| `docs/` | チュートリアル、開発の経緯(`DEVLOG.md`) |

設計の要点: 挙動を変えるときは C(基準)を先に直し、asm を合わせ、`tools/check.sh` で突き合わせます。

## ライセンス
MIT License(`LICENSE`)。`LICENSE` の著作権者名は公開前に実際の名前に書き換えてください。

## 謝辞・関連
- [LSX-Dodgers](https://github.com/tablacus/LSX-Dodgers)(Gaku 氏)— 動作対象の OS(MZ-2500 版は改造版)
- [z88dk](https://github.com/z88dk/z88dk) — ビルドに使用
- [mz2500-web-emulator](https://github.com/zabaglione/mz2500-web-emulator)(Zabaglione 氏)— 動作確認に使用
