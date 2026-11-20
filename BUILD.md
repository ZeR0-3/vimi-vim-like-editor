ビルド・テストの手順は README.md を参照してください。
- Z80 版: `bash tools/bz_build.sh`(フラグ -DMZV_POS32 -DTX_ASM -DR_ASM -DU_ASM -DM_ASM)。`CRENDER=1` で描画だけ C 版にしたビルド(画面比較用の基準)。
- `core/editor.c` が `core/ed_*.c` を #include するユニティビルド。単独ではコンパイルしません。
- `tools/csize.sh`: Z80 版でまだ C のまま残っている関数とそのバイト数。
