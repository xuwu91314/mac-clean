#!/usr/bin/env bash
#
# mac-clean —— 统一入口
#   用法:
#     mac-clean scan [--module all|memory|cache|residual] [--json]
#     mac-clean memory [--top N] [--purge]
#     mac-clean clean-cache [--execute] [--path <p> ...] [--include-tmp]
#     mac-clean clean-residual --path <p> ... [--execute]
#     mac-clean restore [--list|<日期>] [--execute]
#     mac-clean analyze --large [--min 100] [--top 30] [--path <dir> ...]
#     mac-clean analyze --dupes [--min-size 1] [--path <dir> ...]
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUB="${1:-}"; shift || true

case "$SUB" in
  scan)           bash "$DIR/scripts/scan.sh" "$@" ;;
  memory)         bash "$DIR/scripts/memory.sh" "$@" ;;
  clean-cache)    bash "$DIR/scripts/clean_cache.sh" "$@" ;;
  clean-residual) bash "$DIR/scripts/clean_residual.sh" "$@" ;;
  restore)        bash "$DIR/scripts/restore.sh" "$@" ;;
  analyze)        bash "$DIR/scripts/analyze.sh" "$@" ;;
  -h|--help|"")
    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)
    echo "未知子命令: $SUB"; echo "可用: scan | memory | clean-cache | clean-residual | restore | analyze"; exit 1 ;;
esac
