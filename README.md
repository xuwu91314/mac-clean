# mac-clean

安全、可控、可撤销地清理 macOS 内存与磁盘垃圾的 [WorkBuddy](https://www.workbuddy.cn) Skill。

> 版本：v1.0.0 ｜ 许可证：MIT

---

## ✨ 功能

- **内存清理**：只读展示内存状态与高占用进程；`purge` 释放不活跃内存（不 kill 进程、不缓存密码）。
- **磁盘垃圾清理**：按白名单清理应用/系统缓存、日志、临时文件、废纸篓、Xcode 派生数据、浏览器缓存。
- **卸载残留清理**：清理已卸载 App 的支持数据/偏好/容器/启动项，先备份后删、可恢复。
- **大文件 / 重复文件分析**：只读报告（绝不删除），帮定位空间大户与重复副本。
- **自动生成本地一键脚本**（规划中，见 v2）：应对受保护组件、系统级路径、内存 purge 等 AI 删不动的场景。

## 🛡️ 安全特性

- 删除前**完整清单二次确认**，`dry-run` 默认开启。
- `clean_cache.sh` 的 `--execute` 必须同时 `--yes` 才真正删除（双重防御）。
- 卸载残留**强制备份**到 `~/Documents/mac-clean-backup/<日期>/`，可随时 `restore` 恢复。
- **黑名单保护** `/System`、`/usr`、用户文档/照片/邮件等数据绝不动。
- 受保护可执行组件（如 `.BC.D_*`）不在 AI 侧强删，交用户本地终端处理。

## 📦 安装（到 WorkBuddy）

**方式一：从本仓库安装**
```bash
git clone https://github.com/xuwu91314/mac-clean.git
mkdir -p ~/.workbuddy/skills
cp -R mac-clean ~/.workbuddy/skills/mac-clean
```

**方式二：WorkBuddy 技能市场**
在 WorkBuddy 技能市场搜索 `mac-clean` 安装（平台审核通过后可用）。

## 🚀 使用

统一入口 `mac-clean.sh`：

```bash
# 只读扫描（全模块）
bash mac-clean.sh scan --module all

# 内存状态 + 高占用进程
bash mac-clean.sh memory [--top N]

# 释放不活跃内存（需管理员授权，二次确认）
bash mac-clean.sh memory --purge

# 磁盘垃圾清理（先 dry-run 预览，确认后加 --yes）
bash mac-clean.sh clean-cache            # 预览
bash mac-clean.sh clean-cache --execute --yes   # 执行

# 卸载残留（先备份后删）
bash mac-clean.sh clean-residual --path "<残留目录>"

# 恢复误删残留
bash mac-clean.sh restore --list
bash mac-clean.sh restore --execute <日期>

# 大文件 / 重复文件分析（只读，不删）
bash mac-clean.sh analyze --large [--min 100] [--top 30]
bash mac-clean.sh analyze --dupes [--min-size 1] [--path ~/Downloads]
```

## 📂 目录结构

```
mac-clean/
├── SKILL.md                 # 技能定义（触发词/安全铁律/命令表）
├── mac-clean.sh             # 统一入口
├── icon.png                 # 技能图标
├── scripts/
│   ├── scan.sh              # 只读扫描（内存/磁盘/残留）
│   ├── memory.sh            # 内存状态 + purge
│   ├── clean_cache.sh       # 磁盘垃圾清理
│   ├── clean_residual.sh    # 卸载残留清理（先备份后删）
│   ├── restore.sh           # 从备份恢复
│   └── analyze.sh           # 大文件/重复文件分析（只读）
├── references/
│   └── safe_paths.md        # 白名单/黑名单与风险边界
└── V2-PLAN.md               # 第二版功能规划
```

## ⚠️ 已知限制

- 系统级路径（`/Library/Caches`、`/Library/Logs`）与 `sudo purge` 需本地管理员授权，AI 侧无法代点密码窗。
- 含受保护可执行组件的 App 残留无法在 AI 侧备份/删除，需本地终端处理。
- 卸载残留的"可能孤儿"为启发式判断，误报率较高，删除前务必逐条核对真实卸载状态。

## 📄 许可证

[MIT](LICENSE) © 2026 mac-clean contributors
