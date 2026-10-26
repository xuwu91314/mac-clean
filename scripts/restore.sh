#!/usr/bin/env bash
#
# mac-clean / scripts / restore.sh
# ---------------------------------------------------------------
# 从备份恢复被清理的卸载残留。备份位于 ~/Documents/mac-clean-backup/<日期>/，
# 结构为 Home/<相对路径> 与 Root/<绝对路径>。恢复只复制、不删除任何东西。
#
# 用法:
#   restore.sh --list                 # 列出可用备份日期
#   restore.sh <日期>                 # 预览该日期的恢复
#   restore.sh --execute <日期>       # 实际恢复
# ---------------------------------------------------------------

set -uo pipefail

MODE="dry-run"
DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute) MODE="execute"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --list)    MODE="list"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) DATE="$1"; shift ;;
  esac
done

BACKUP_ROOT="$HOME/Documents/mac-clean-backup"

if [[ "$MODE" == "list" ]]; then
  echo "Available backup dates:"
  if [[ -d "$BACKUP_ROOT" ]]; then
    ls -1 "$BACKUP_ROOT" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
  else
    echo "  (no backup dir: $BACKUP_ROOT)"
  fi
  exit 0
fi

if [[ -z "$DATE" ]]; then
  echo "Usage: restore.sh --list | restore.sh [--execute] <date>"
  exit 1
fi

SRC="$BACKUP_ROOT/$DATE"
if [[ ! -d "$SRC" ]]; then
  echo "Backup not found: $SRC"
  exit 1
fi

echo "=================================================="
echo " Restore backup - $([[ "$MODE" == "execute" ]] && echo "EXECUTE" || echo "dry-run")"
echo " Source: $SRC"
echo "=================================================="

restore_home() {
  local s="$SRC/Home"
  [[ -d "$s" ]] || return 0
  if [[ "$MODE" == "execute" ]]; then
    ditto "$s" "$HOME" 2>/dev/null && echo "  OK restored user-level files to HOME" \
      || echo "  WARN user-level restore failed"
  else
    echo "  [preview] will restore user-level: $s -> HOME/"
  fi
}
restore_root() {
  local s="$SRC/Root"
  [[ -d "$s" ]] || return 0
  if [[ "$MODE" == "execute" ]]; then
    osascript -e "do shell script \"ditto '${s}' '/'\"" with administrator privileges 2>/dev/null \
      && echo "  OK restored system-level files (admin required)" \
      || echo "  WARN system-level restore needs admin; skipped"
  else
    echo "  [preview] will restore system-level (admin): $s -> /"
  fi
}

restore_home
restore_root

echo "=================================================="
if [[ "$MODE" != "execute" ]]; then
  echo "(dry-run: nothing written. Add --execute to perform restore.)"
fi
