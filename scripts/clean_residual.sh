#!/usr/bin/env bash
#
# mac-clean / scripts / clean_residual.sh
# ---------------------------------------------------------------
# 卸载残留清理。默认 dry-run 仅预览。--execute 前先【备份】到
# ~/Documents/mac-clean-backup/<日期>/（保留 Home/Root 目录结构），再删除。
# 安全：绝不 kill 进程；系统级启动项走管理员授权；删除前强制备份（可恢复）。
#
# 用法:
#   clean_residual.sh --path <路径> ...        # 指定残留项（可多次）
#   clean_residual.sh --dry-run --path <路径>  # 预览（默认）
#   clean_residual.sh --execute --path <路径>  # 备份并删除
# ---------------------------------------------------------------

set -uo pipefail

MODE="dry-run"
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) MODE="execute"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --path)    TARGETS+=("$2"); shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

if (( ${#TARGETS[@]} == 0 )); then
  echo "请通过 --path 指定要清理的残留路径（可参考 scan.sh --module residual 的输出）。"
  exit 1
fi

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
  [[ "$1" == /Library/* || "$1" == /System/* ]]
}

BACKUP_ROOT="$HOME/Documents/mac-clean-backup"
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="$BACKUP_ROOT/$DATE"

echo "=================================================="
echo " 卸载残留清理 —— $([[ "$MODE" == "execute" ]] && echo "执行模式(先备份后删除)" || echo "预览模式(dry-run)")"
echo " 备份目录: $BACKUP_DIR"
echo "=================================================="

for target in "${TARGETS[@]}"; do
  if [[ ! -e "$target" ]]; then
    echo "  [跳过] 不存在: $target"
    continue
  fi
  b=$(dir_bytes "$target"); h=$(to_human "$b")
  # 计算备份目标（保留 Home/Root 结构，便于原样恢复）
  if [[ "$target" == "$HOME"/* ]]; then
    rel="${target#$HOME/}"; dest="$BACKUP_DIR/Home/$rel"
  else
    dest="$BACKUP_DIR/Root$target"
  fi

  if [[ "$MODE" == "execute" ]]; then
    mkdir -p "$(dirname "$dest")"
    if ditto "$target" "$dest" 2>/dev/null; then
      echo "  ✓ 已备份: $dest"
    else
      echo "  ⚠ 备份失败，已中止删除（安全起见）: $target"
      continue
    fi
    if is_system "$target"; then
      osascript -e "do shell script \"rm -rf '${target}'\"" with administrator privileges 2>/dev/null \
        && echo "  ✓ 已删除(系统): $target ($h)" \
        || echo "  ⚠ 系统路径删除需管理员授权，已跳过: $target"
    else
      rm -rf "$target" 2>/dev/null && echo "  ✓ 已删除: $target ($h)" \
        || echo "  ⚠ 删除失败: $target"
    fi
  else
    printf "  %9s  [预览] 将备份到: %s\n" "$h" "$dest"
    echo "           [预览] 将删除: $target"
  fi
done

echo "=================================================="
if [[ "$MODE" != "execute" ]]; then
  echo "（预览模式不会删除。确认后加 --execute；删除前会自动备份，可用 restore.sh 恢复。）"
else
  echo "执行完成。如需恢复：bash scripts/restore.sh --execute $DATE"
fi
