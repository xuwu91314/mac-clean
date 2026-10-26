#!/usr/bin/env bash
#
# mac-clean / scripts / clean_cache.sh
# ---------------------------------------------------------------
# 磁盘垃圾清理（白名单）。默认 dry-run 仅预览，--execute 才删除。
# 安全：只删白名单路径的【内容】（保留父目录）；系统级路径走管理员授权；
#       绝不碰 /System、/usr、用户文档等黑名单；缓存类可再生，不备份。
#
# 用法:
#   clean_cache.sh                       # 默认 dry-run，预览全部白名单
#   clean_cache.sh --execute --yes       # 实际清理全部白名单（--yes 为明确确认）
#   clean_cache.sh --path <路径> ...     # 仅清理指定路径（可多次）
#   clean_cache.sh --include-tmp         # 额外包含 /tmp、/private/var/tmp（谨慎）
# 安全：--execute 必须配合 --yes 才真正删除，否则仅预览（防误触发）。
# ---------------------------------------------------------------

set -uo pipefail

MODE="dry-run"
CONFIRM=0
TARGETS=()
INCLUDE_TMP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)    MODE="execute"; shift ;;
    --dry-run)    MODE="dry-run"; shift ;;
    --yes)        CONFIRM=1; shift ;;
    --path)       TARGETS+=("$2"); shift 2 ;;
    --include-tmp) INCLUDE_TMP=1; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

to_human() {
  local b="$1"
  if [[ -z "$b" || "$b" == "0" ]]; then echo "0B"; return; fi
  numfmt --to=iec --suffix=B "$b" 2>/dev/null || \
    awk -v b="$b" 'BEGIN{ u="BKMGT"; i=0; while(b>=1024 && i<4){b/=1024;i++} printf "%.1f%s", b, substr(u,i+1,1)}'
}
dir_bytes() {
  local p="$1" kb
  [[ -e "$p" ]] || { echo 0; return; }
  kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
  echo $(( ${kb:-0} * 1024 ))
}
is_system() {
  [[ "$1" == /Library/* || "$1" == /System/* || "$1" == /tmp/* || "$1" == /private/var/tmp/* ]]
}

# 默认白名单（用户级，可安全清理）
PATHS=(
  "$HOME/Library/Caches"
  "$HOME/Library/Logs"
  "$HOME/Library/DiagnosticReports"
  "$HOME/.Trash"
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/Xcode/Archives"
)
[[ -d "$HOME/Library/Caches/Google/Chrome" ]]   && PATHS+=("$HOME/Library/Caches/Google/Chrome")
[[ -d "$HOME/Library/Caches/com.apple.Safari" ]] && PATHS+=("$HOME/Library/Caches/com.apple.Safari")
[[ -d "$HOME/Library/Caches/Firefox" ]]          && PATHS+=("$HOME/Library/Caches/Firefox")

# 系统级（需管理员授权）
SYSTEM_PATHS=("/Library/Caches" "/Library/Logs")
(( INCLUDE_TMP )) && SYSTEM_PATHS+=("/tmp" "/private/var/tmp")

if (( ${#TARGETS[@]} > 0 )); then
  ALL=("${TARGETS[@]}")
else
  ALL=("${PATHS[@]}" "${SYSTEM_PATHS[@]}")
fi

# 构建清单
declare -a M_PATH=() M_SIZE=() M_SYS=()
TOTAL=0
for p in "${ALL[@]}"; do
  [[ -e "$p" ]] || { echo "  [跳过] 不存在: $p"; continue; }
  b=$(dir_bytes "$p"); h=$(to_human "$b")
  TOTAL=$((TOTAL + b))
  M_PATH+=("$p"); M_SIZE+=("$b"); M_SYS+=("$(is_system "$p" && echo 1 || echo 0)")
done

echo "=================================================="
echo " 磁盘垃圾清理 —— $([[ "$MODE" == "execute" ]] && echo "执行模式" || echo "预览模式(dry-run)")"
echo "=================================================="
if (( ${#M_PATH[@]} == 0 )); then
  echo "  无可清理项。"
  exit 0
fi
echo "将清理以下白名单路径的【内容】（保留父目录）："
for i in "${!M_PATH[@]}"; do
  if (( ${M_SYS[$i]} )); then sf="  [系统·管理员]"; else sf=""; fi
  printf "  %9s  %s%s\n" "$(to_human ${M_SIZE[$i]})" "${M_PATH[$i]}" "$sf"
done
echo "--------------------------------------------------"
echo "预计释放: $(to_human $TOTAL)"
echo "=================================================="

if [[ "$MODE" != "execute" ]]; then
  echo "（预览模式不会删除任何文件。确认后加 --execute --yes 执行；系统路径将弹出管理员授权。）"
  exit 0
fi

if (( CONFIRM != 1 )); then
  echo "⚠ 安全拦截：--execute 必须同时指定 --yes 才执行真实删除。"
  echo "   （请确认已向用户展示完整清单并获得明确同意后再加 --yes。）"
  exit 1
fi

echo ">>> 开始执行清理..."
for i in "${!M_PATH[@]}"; do
  p="${M_PATH[$i]}"
  if (( ${M_SYS[$i]} )); then
    echo "  [系统] 清空内容: $p"
    osascript -e "do shell script \"find '${p}' -mindepth 1 -maxdepth 1 -exec rm -rf {} +\"" with administrator privileges 2>/dev/null \
      || echo "    ⚠ 系统路径清理需管理员授权，已跳过（或授权失败）。"
  else
    echo "  [用户] 清空内容: $p"
    find "$p" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  fi
done
echo ">>> 清理完成。缓存类文件可再生，相关应用首次启动可能略慢（正常）。"
