#!/usr/bin/env bash
#
# mac-clean / scripts / memory.sh
# ---------------------------------------------------------------
# 内存清理：
#   - 只读：展示内存状态（vm_stat / memory_pressure / sysctl）与高占用进程
#   - 执行：在用户确认后释放不活跃内存（purge）
# 安全：绝不 kill 任何进程；purge 通过 macOS 原生管理员授权弹窗或 sudo 执行，不缓存密码。
#
# 用法:
#   memory.sh                 # 仅展示状态（默认，只读）
#   memory.sh --top N         # 展示前 N 个高内存进程（默认 10）
#   memory.sh --purge         # 确认后执行 purge（需管理员授权）
#   memory.sh --purge --top N # purge 后展示对比 + 前 N 进程
# ---------------------------------------------------------------

set -uo pipefail

ACTION="status"
TOPN=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)  ACTION="purge"; shift ;;
    --status) ACTION="status"; shift ;;
    --top)    TOPN="${2:-10}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || getconf PAGESIZE 2>/dev/null || echo 4096)
PHYS_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)

to_human() {
  local b="$1"
  if [[ -z "$b" || "$b" == "0" ]]; then echo "0B"; return; fi
  numfmt --to=iec --suffix=B "$b" 2>/dev/null || \
    awk -v b="$b" 'BEGIN{ u="BKMGT"; i=0; while(b>=1024 && i<4){b/=1024;i++} printf "%.1f%s", b, substr(u,i+1,1)}'
}

# 读取 vm_stat 关键页数字（返回若干变量）
read_vm() {
  local vm pfree pactive pinact pspec pwired pcomp freeb activeb inactb specb wiredb compb
  vm=$(vm_stat 2>/dev/null) || return 1
  pfree=$(echo "$vm"  | awk -F: '/Pages free:/{gsub(/[. ]/,"");print $2}')
  pactive=$(echo "$vm"  | awk -F: '/Pages active:/{gsub(/[. ]/,"");print $2}')
  pinact=$(echo "$vm"   | awk -F: '/Pages inactive:/{gsub(/[. ]/,"");print $2}')
  pspec=$(echo "$vm"    | awk -F: '/Pages speculative:/{gsub(/[. ]/,"");print $2}')
  pwired=$(echo "$vm"   | awk -F: '/Pages wired down:/{gsub(/[. ]/,"");print $2}')
  pcomp=$(echo "$vm"    | awk -F: '/Pages occupied by compressor:/{gsub(/[. ]/,"");print $2}')
  freeb=$(( ${pfree:-0}   * PAGE_SIZE ))
  activeb=$(( ${pactive:-0} * PAGE_SIZE ))
  inactb=$(( ${pinact:-0}  * PAGE_SIZE ))
  specb=$(( ${pspec:-0}   * PAGE_SIZE ))
  wiredb=$(( ${pwired:-0}  * PAGE_SIZE ))
  compb=$(( ${pcomp:-0}   * PAGE_SIZE ))
  # 通过全局名返回（函数内 local 不便跨函数，这里用 echo 行协议）
  echo "$freeb|$activeb|$inactb|$specb|$wiredb|$compb"
}

pressure_of() {
  # 参数: free_bytes；返回压力等级文本
  local freeb="$1" mp swapouts swapins
  mp=$(memory_pressure 2>/dev/null)
  swapouts=$(echo "$mp" | awk '/Swapouts:/{print $2}')
  swapins=$(echo   "$mp" | awk '/Swapins:/{print $2}')
  if (( ${swapouts:-0} > 0 || ${swapins:-0} > 0 )); then
    echo "critical (已触发交换)"
  elif (( freeb < 200*1024*1024 )); then
    echo "warn (空闲偏低)"
  else
    echo "normal"
  fi
}

print_status() {
  local snap freeb activeb inactb specb wiredb compb pressure
  snap=$(read_vm) || { echo "无法读取 vm_stat"; return 1; }
  IFS='|' read -r freeb activeb inactb specb wiredb compb <<< "$snap"
  pressure=$(pressure_of "$freeb")

  echo "=================================================="
  echo " 内存状态"
  echo "=================================================="
  echo "  物理内存   : $(to_human ${PHYS_BYTES:-0})"
  echo "  空闲       : $(to_human ${freeb:-0})"
  echo "  活跃       : $(to_human ${activeb:-0})"
  echo "  不活跃     : $(to_human ${inactb:-0})"
  echo "  联动(wired): $(to_human ${wiredb:-0})"
  echo "  压缩       : $(to_human ${compb:-0})"
  echo "  内存压力   : $pressure"
  echo ""
  echo "  高内存占用进程 (Top $TOPN)："
  local procs
  procs=$(ps -ax -o pid=,rss=,comm= 2>/dev/null | sort -k2 -nr | head -n "$TOPN")
  if [[ -z "$procs" ]]; then
    echo "    （无法读取进程列表；若运行环境限制 ps，请在终端直接运行本脚本）"
  else
    echo "$procs" | awk '{printf "    %6s  %8.1fM  %s\n", $1, $2/1024, $3}'
  fi
  echo ""
  echo "  说明: purge 仅释放『不活跃内存』，不影响运行中的应用数据安全；"
  echo "        不 kill 任何进程。应用缓存释放后首次启动可能略慢（正常）。"
}

do_purge() {
  echo "准备执行 purge（释放不活跃内存）..."
  # 优先：macOS 原生管理员授权弹窗（GUI 会话下可用，不缓存密码）
  if command -v osascript >/dev/null 2>&1; then
    if osascript -e 'do shell script "/usr/sbin/purge" with administrator privileges' 2>/dev/null; then
      echo "✓ purge 已通过管理员授权执行。"
      return 0
    fi
  fi
  # 回退：若已配置 sudo 免密（如已缓存凭证），直接 sudo
  if sudo -n true 2>/dev/null; then
    if sudo /usr/sbin/purge 2>/dev/null; then
      echo "✓ purge 已通过 sudo 执行。"
      return 0
    fi
  fi
  # 最终回退：提示手动执行
  echo "⚠ 无法自动获得管理员授权（非 GUI 会话或未授权）。请手动在终端执行："
  echo "    sudo purge"
  return 1
}

###
### 主流程
###
if [[ "$ACTION" == "purge" ]]; then
  echo ">>> 执行前内存状态："
  print_status
  if do_purge; then
    echo ""
    echo ">>> 执行后内存状态（对比）："
    print_status
  fi
else
  print_status
fi
