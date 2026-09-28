#!/usr/bin/env bash
# 截图：tools/shot.sh <godot> <shot名> <输出png> [额外参数...]
# 优先使用 Vulkan（Forward+，需要 lavapipe 等），设置 SHOT_GL=1 使用兼容渲染器。
set -u
GODOT="$1"; SHOT="$2"; OUT="$3"; shift 3
cd "$(dirname "$0")/.."
# 刷新全局类缓存与资源导入
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
if [ "${SHOT_GL:-0}" = "1" ]; then
	R=(--rendering-driver opengl3 --rendering-method gl_compatibility)
else
	export VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}
	R=(--rendering-driver vulkan --rendering-method forward_plus)
fi
timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" "${R[@]}" --path . res://tools/shots/shot_runner.tscn -- --shot="$SHOT" --out="$OUT" "$@" 2>&1 | grep -vE "ALSA|alsa|audio|pulse|^\s*$" | tail -15
