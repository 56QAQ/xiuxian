#!/usr/bin/env bash
# 运行无头测试。用法：tools/run_tests.sh [godot 可执行文件] [--filter=关键字]
# 除测试自身断言外，输出中出现任何脚本错误也视为失败。
set -u
GODOT="${1:-${GODOT:-godot}}"
shift || true
cd "$(dirname "$0")/.."
# 刷新全局类缓存与资源导入
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1
OUT=$(timeout 600 "$GODOT" --headless --path . res://tests/test_runner.tscn -- "$@" 2>&1)
CODE=$?
echo "$OUT" | grep -vE "^\s*$|ALSA|alsa|audio driver|pulse"
if echo "$OUT" | grep -vE "audio|ALSA|alsa|init_output_device" | grep -qE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|^ERROR:"; then
	echo "检测到脚本错误"
	exit 1
fi
exit $CODE
