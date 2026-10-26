#!/usr/bin/env bash
#
# mac-clean / scripts / scan.sh
# ---------------------------------------------------------------
# 只读扫描 macOS：
#   - 内存状态（vm_stat / memory_pressure / sysctl hw.memsize）
#   - 磁盘垃圾体积（白名单路径）
#   - 应用卸载残留（孤儿探测，启发式）
# 不创建、不修改、不删除任何文件。所有删除由 P2-P4 的清理脚本负责。
#
# 用法:
#   scan.sh [--module memory|cache|residual|all] [--json] [-h|--help]
# ---------------------------------------------------------------

set -uo pipefail

MODULE="all"
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) MODULE="${2:-all}"; shift 2 ;;
    --json)   JSON=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

# 记录格式:  CATEGORY<TAB>KEY<TAB>VALUE   (VALUE 内部用 | 分隔子字段)
emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || getconf PAGESIZE 2>/dev/null || echo 4096)
PHYS_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)

to_human() {
  local b="$1"
  if [[ -z "$b" || "$b" == "0" ]]; then echo "0B"; return; fi
  numfmt --to=iec --suffix=B "$b" 2>/dev/null || \
    awk -v b="$b" 'BEGIN{ u="BKMGT"; i=0; while(b>=1024 && i<4){b/=1024;i++} printf "%.1f%s", b, substr(u,i+1,1)}'
}

dir_bytes() {
  # 输入路径，输出字节（du -sk 的 KB * 1024）；不存在返回 0
  # 注意：BSD du 不允许 -s 与 -d 同时使用，故只用 -sk
  local p="$1" kb
  [[ -e "$p" ]] || { echo 0; return; }
  kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
  echo $(( ${kb:-0} * 1024 ))
}

###
### 模块一：内存
###
scan_memory() {
  local vm
  vm=$(vm_stat 2>/dev/null) || { emit "memory" "error" "vm_stat 不可用"; return; }

  local pfree pactive pinact pspec pwired pcomp
  pfree=$(echo "$vm"  | awk -F: '/Pages free:/{gsub(/[. ]/,"");print $2}')
  pactive=$(echo "$vm"  | awk -F: '/Pages active:/{gsub(/[. ]/,"");print $2}')
  pinact=$(echo "$vm"   | awk -F: '/Pages inactive:/{gsub(/[. ]/,"");print $2}')
  pspec=$(echo "$vm"    | awk -F: '/Pages speculative:/{gsub(/[. ]/,"");print $2}')
  pwired=$(echo "$vm"   | awk -F: '/Pages wired down:/{gsub(/[. ]/,"");print $2}')
  pcomp=$(echo "$vm"    | awk -F: '/Pages occupied by compressor:/{gsub(/[. ]/,"");print $2}')

  emit "memory" "physical_bytes"  "$PHYS_BYTES"
  emit "memory" "free_bytes"      $(( ${pfree:-0}   * PAGE_SIZE ))
  emit "memory" "active_bytes"    $(( ${pactive:-0} * PAGE_SIZE ))
  emit "memory" "inactive_bytes"  $(( ${pinact:-0}  * PAGE_SIZE ))
  emit "memory" "speculative_bytes" $(( ${pspec:-0} * PAGE_SIZE ))
  emit "memory" "wired_bytes"     $(( ${pwired:-0}  * PAGE_SIZE ))
  emit "memory" "compressed_bytes" $(( ${pcomp:-0}  * PAGE_SIZE ))

  # 内存压力启发式：优先看交换活动，其次看空闲是否偏低
  local mp swapouts swapins pressure
  mp=$(memory_pressure 2>/dev/null)
  swapouts=$(echo "$mp" | awk '/Swapouts:/{print $2}')
  swapins=$(echo   "$mp" | awk '/Swapins:/{print $2}')
  if (( ${swapouts:-0} > 0 || ${swapins:-0} > 0 )); then
    pressure="critical (已触发交换)"
  elif (( ${pfree:-0} * PAGE_SIZE < 200*1024*1024 )); then
    pressure="warn (空闲偏低)"
  else
    pressure="normal"
  fi
  emit "memory" "pressure" "$pressure"
}

###
### 模块二：磁盘垃圾（白名单）
###
DISK_PATHS=(
  "$HOME/Library/Caches"
  "/Library/Caches"
  "$HOME/Library/Logs"
  "/Library/Logs"
  "$HOME/Library/DiagnosticReports"
  "/private/var/tmp"
  "$HOME/.Trash"
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/Xcode/Archives"
)

detect_browser_caches() {
  [[ -d "$HOME/Library/Caches/Google/Chrome" ]]    && DISK_PATHS+=("$HOME/Library/Caches/Google/Chrome")
  [[ -d "$HOME/Library/Caches/com.apple.Safari" ]] && DISK_PATHS+=("$HOME/Library/Caches/com.apple.Safari")
  [[ -d "$HOME/Library/Caches/Firefox" ]]          && DISK_PATHS+=("$HOME/Library/Caches/Firefox")
}

scan_disk() {
  detect_browser_caches
  local path b h
  for path in "${DISK_PATHS[@]}"; do
    if [[ -e "$path" ]]; then
      b=$(dir_bytes "$path"); h=$(to_human "$b")
      emit "disk" "$path" "$b|$h"
    else
      emit "disk" "$path" "missing"
    fi
  done
}

###
### 模块三：卸载残留（孤儿探测，启发式，需二次确认）
###
app_exists() {
  local n="$1" f
  [[ -e "/Applications/$n.app" ]]      && return 0
  [[ -e "$HOME/Applications/$n.app" ]] && return 0
  for f in /Applications/*"$n"*.app;        do [[ -e "$f" ]] && return 0; done
  for f in "$HOME/Applications/"*"$n"*.app; do [[ -e "$f" ]] && return 0; done
  return 1
}

scan_residual_dir() {
  local base="$1" label="$2" entry name b h orphan
  [[ -d "$base" ]] || return 0
  for entry in "$base"/*; do
    [[ -e "$entry" ]] || continue
    name=$(basename "$entry")
    b=$(dir_bytes "$entry"); h=$(to_human "$b")
    # 仅展示 >=1MB 的条目（LaunchAgents 例外，保留小体积启动项），过滤系统小配置目录噪声
    if [[ "$label" != "LaunchAgent" ]] && (( b < 1048576 )); then continue; fi
    if app_exists "$name"; then orphan="no"; else orphan="possibly"; fi
    emit "residual" "$label::$name" "$b|$h|$orphan"
  done
}

scan_residual() {
  scan_residual_dir "$HOME/Library/Application Support" "AppSupport"
  scan_residual_dir "$HOME/Library/Caches"              "Cache"
  scan_residual_dir "$HOME/Library/Containers"          "Container"
  scan_residual_dir "$HOME/Library/LaunchAgents"        "LaunchAgent"
}

###
### 收集
###
RECORDS=""
[[ "$MODULE" == "all" || "$MODULE" == "memory" ]]   && RECORDS+="$(scan_memory)"
[[ "$MODULE" == "all" || "$MODULE" == "cache" ]]    && RECORDS+="$(scan_disk)"
[[ "$MODULE" == "all" || "$MODULE" == "residual" ]] && RECORDS+="$(scan_residual)"

###
### 渲染
###
if [[ "$JSON" == "1" ]]; then
  # 注意：heredoc 会占用 python 的 stdin，故数据通过环境变量传入，避免管道与 heredoc 冲突
  RECORDS_JSON="$RECORDS" python3 - <<'PY'
import os, json
data = {"memory": {}, "disk": {}, "residual": {}}
for line in os.environ.get("RECORDS_JSON", "").splitlines():
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) < 3:
        continue
    cat, key, val = parts[0], parts[1], parts[2]
    if cat == "memory":
        data["memory"][key] = val
    elif cat == "disk":
        if val == "missing":
            data["disk"][key] = {"exists": False}
        else:
            b, h = val.split("|", 1)
            data["disk"][key] = {"exists": True, "bytes": int(b), "human": h}
    elif cat == "residual":
        label, name = key.split("::", 1)
        b, h, orphan = val.split("|", 2)
        data["residual"].setdefault(label, []).append(
            {"name": name, "bytes": int(b), "human": h, "orphan": orphan})
print(json.dumps(data, ensure_ascii=False, indent=2))
PY
else
  echo "=================================================="
  echo " mac-clean 扫描报告（只读，未做任何改动）"
  echo " 模块: $MODULE"
  echo "=================================================="

  if [[ "$MODULE" == "all" || "$MODULE" == "memory" ]]; then
    echo ""
    echo "【内存】"
    phys=$(echo "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="physical_bytes"{print $3}')
    free=$(echo "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="free_bytes"{print $3}')
    act=$(echo  "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="active_bytes"{print $3}')
    ina=$(echo  "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="inactive_bytes"{print $3}')
    wir=$(echo  "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="wired_bytes"{print $3}')
    com=$(echo  "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="compressed_bytes"{print $3}')
    pres=$(echo "$RECORDS" | awk -F'\t' '$1=="memory"&&$2=="pressure"{print $3}')
    echo "  物理内存   : $(to_human ${phys:-0})"
    echo "  空闲       : $(to_human ${free:-0})"
    echo "  活跃       : $(to_human ${act:-0})"
    echo "  不活跃     : $(to_human ${ina:-0})"
    echo "  联动(wired): $(to_human ${wir:-0})"
    echo "  压缩       : $(to_human ${com:-0})"
    echo "  内存压力   : ${pres:-unknown}"
  fi

  if [[ "$MODULE" == "all" || "$MODULE" == "cache" ]]; then
    echo ""
    echo "【磁盘垃圾（白名单，可清理）】"
    echo "$RECORDS" | awk -F'\t' '$1=="disk"{
      if ($3 == "missing") { printf "  [不存在]    %s\n", $2 }
      else { n=split($3,a,"|"); printf "  %9s  %s\n", a[2], $2 }
    }'
  fi

  if [[ "$MODULE" == "all" || "$MODULE" == "residual" ]]; then
    echo ""
    echo "【卸载残留（孤儿探测，需二次确认）】"
    echo "$RECORDS" | awk -F'\t' '$1=="residual"{
      n=split($2,lab,"::"); split($3,b,"|");
      flag = (b[3]=="possibly") ? "  <-- 可能孤儿" : "";
      printf "  %9s  [%-11s] %s%s\n", b[2], lab[1], lab[2], flag
    }'
  fi

  echo ""
  echo "提示: 以上仅为预览。实际清理需用户确认后由 P2-P4 清理脚本执行。"
fi
