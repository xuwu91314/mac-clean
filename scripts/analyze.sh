#!/usr/bin/env bash
#
# mac-clean · analyze.sh —— 大文件 / 重复文件分析（只读报告，绝不删除）
#
# 用法:
#   analyze.sh --large [--min 100] [--top 30] [--path <dir> ...]
#   analyze.sh --dupes [--min-size 1] [--path <dir> ...]
#   analyze.sh --help
#
# 安全:
#   - 仅扫描用户内容目录（Downloads/Documents/Desktop/Movies/Music/Pictures），
#     排除 node_modules/.git/.Trash/Library/Caches/.cache/build，避免误报与卡顿。
#   - 只产出报告，不删除任何文件。如需清理，请走 clean 流程并二次确认。
#
set -uo pipefail

MODE=""
MIN_MB=100          # --large 阈值（MB）
TOP_N=30            # --large 展示条数
DUP_MIN_MB=1        # --dupes 最小文件尺寸（MB）
PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --large)    MODE="large"; shift ;;
    --dupes)    MODE="dupes"; shift ;;
    --min)      MIN_MB="$2"; shift 2 ;;
    --top)      TOP_N="$2"; shift 2 ;;
    --min-size) DUP_MIN_MB="$2"; shift 2 ;;
    --path)     PATHS+=("$2"); shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "请指定 --large 或 --dupes。"; echo "用法见 analyze.sh --help"; exit 1
fi

# 默认限定目录；用户也可 --path 自定义
DEFAULT_DIRS=("$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" "$HOME/Movies" "$HOME/Music" "$HOME/Pictures")
if [[ ${#PATHS[@]} -eq 0 ]]; then
  PATHS=("${DEFAULT_DIRS[@]}")
fi

SCAN_DIRS=()
for d in "${PATHS[@]}"; do
  [[ -d "$d" ]] && SCAN_DIRS+=("$d")
done
if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  echo "没有可扫描的目录（给定路径均不存在）。"
  exit 1
fi

# 排除项：开发依赖 / 系统缓存 / 废纸篓，避免误报与卡顿
EXCLUDES=(
  -not -path '*/node_modules/*'
  -not -path '*/.git/*'
  -not -path '*/.Trash/*'
  -not -path '*/Library/Caches/*'
  -not -path '*/.cache/*'
  -not -path '*/build/*'
  -not -path '*/.venv/*'
  -not -path '*/venv/*'
  -not -path '*/site-packages/*'
  -not -path '*/dist/*'
  -not -path '*/.tox/*'
  -not -path '*/__pycache__/*'
  -not -path '*/standalone-env/*'
)

to_human() {
  local b="$1"
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB", u, " "); i=1;
    while (b>=1024 && i<5){ b/=1024; i++ }
    if (i==1) printf "%.0f%s", b, u[i];
    else printf "%.1f%s", b, u[i];
  }'
}

echo "扫描范围: ${SCAN_DIRS[*]}"
echo ""

if [[ "$MODE" == "large" ]]; then
  MINBYTES=$(( MIN_MB * 1024 * 1024 ))
  echo ">>> 大文件分析（≥ ${MIN_MB}MB，Top ${TOP_N}）"
  echo "  路径 | 体积"
  echo "  ----------------------------------------"
  find "${SCAN_DIRS[@]}" -type f "${EXCLUDES[@]}" -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        sz=$(stat -f%z "$f" 2>/dev/null) || continue
        if (( sz >= MINBYTES )); then
          printf '%s\t%s\n' "$sz" "$f"
        fi
      done \
    | sort -nr | head -n "$TOP_N" \
    | while IFS=$'\t' read -r sz f; do
        printf '  %-10s %s\n' "$(to_human "$sz")" "$f"
      done
  echo ""
  echo "（仅报告，不删除。确认无用后可手动删除或走 clean 流程）"

elif [[ "$MODE" == "dupes" ]]; then
  DUP_MINBYTES=$(( DUP_MIN_MB * 1024 * 1024 ))
  TMPF="$(mktemp)"
  echo ">>> 重复文件分析（文件 ≥ ${DUP_MIN_MB}MB，按 体积+sha256 比对）"
  find "${SCAN_DIRS[@]}" -type f "${EXCLUDES[@]}" -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        sz=$(stat -f%z "$f" 2>/dev/null) || continue
        if (( sz >= DUP_MINBYTES )); then
          printf '%s\t%s\n' "$sz" "$f"
        fi
      done > "$TMPF"

  python3 - "$TMPF" <<'PY'
import sys, hashlib

def to_human_safe(b):
    units = ["B","KB","MB","GB","TB"]
    i = 0
    while b >= 1024 and i < 4:
        b /= 1024.0; i += 1
    return f"{b:.1f}{units[i]}" if i else f"{int(b)}B"

tmp = sys.argv[1]
by_size = {}
with open(tmp) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        sz, path = line.split("\t", 1)
        sz = int(sz)
        by_size.setdefault(sz, []).append(path)

# 仅保留 size 出现 >=2 的组，进一步按 hash 分组
groups = []           # list of (size, [paths])
total_files = 0
for sz, paths in by_size.items():
    if len(paths) < 2:
        continue
    by_hash = {}
    for p in paths:
        try:
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(1<<20), b""):
                    h.update(chunk)
            by_hash.setdefault(h.hexdigest(), []).append(p)
        except OSError:
            continue
    for h, ps in by_hash.items():
        if len(ps) >= 2:
            groups.append((sz, ps))
            total_files += len(ps)

groups.sort(key=lambda g: g[0]*(len(g[1])-1), reverse=True)
print(f"  扫描文件数(≥阈值): {sum(len(v) for v in by_size.values())}")
print(f"  重复组数: {len(groups)}  涉及文件: {total_files}")
print()
reclaim = 0
for sz, ps in groups:
    reclaim += sz * (len(ps) - 1)
    print(f"  ╔ 重复组  {len(ps)} 份 × {sz/1024/1024:.1f}MB  → 可释放 {to_human_safe(sz*(len(ps)-1))}")
    for p in ps:
        print(f"  ║   {p}")
    print(f"  ╚ 删除其中 {len(ps)-1} 份可释放 {to_human_safe(sz*(len(ps)-1))}")
    print()
print(f"  ★ 预计可释放（仅删除重复副本）: {to_human_safe(reclaim)}")
PY
  rm -f "$TMPF"
  echo ""
  echo "（仅报告，不删除。删除重复副本前请确认保留哪一份，避免误删唯一文件）"
fi
