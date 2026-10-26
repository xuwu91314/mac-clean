---
name: mac-clean
description: 安全、可控、可撤销地清理 macOS 内存与磁盘垃圾（应用与系统缓存、日志、临时文件、废纸篓、Xcode 派生数据、浏览器缓存）以及应用卸载后的残留（支持数据、偏好、容器、启动项）。当用户的请求涉及清理 Mac 内存、释放内存、清理磁盘缓存、清理日志、清理废纸篓、清理 Xcode 垃圾、清理浏览器缓存、清理应用卸载残留或分析大文件与重复文件时使用。所有删除操作必须先扫描预览、展示完整清单并获得用户二次确认，严格遵守白名单与系统安全边界，绝不触碰 /System、/usr、用户文档、照片、邮件等数据。
version: 1.0.0
agent_created: true
display_name: macOS 清理助手
display_name_en: mac-clean
description_zh: 安全清理 macOS 内存与磁盘垃圾（应用与系统缓存、日志、临时文件、废纸篓、Xcode 派生数据、浏览器缓存）、应用卸载残留，并支持大文件/重复文件只读分析。所有删除先预览、二次确认、可撤销，严守系统安全边界。
description_en: Safely clean macOS memory and disk junk (app & system caches, logs, temp, trash, Xcode DerivedData, browser caches), app-uninstall leftovers, and analyze large/duplicate files read-only. Every deletion is previewed, confirmed, and reversible.
---

# mac-clean

macOS 清理助手。安全、可控、可撤销地清理内存与磁盘垃圾、应用卸载残留，并支持大文件/重复文件只读分析。

## 何时使用
- 用户说「清理 mac 内存 / 释放内存 / 内存不够了」。
- 用户说「清理磁盘垃圾 / 清理缓存 / 清理日志 / 清理废纸篓 / 清理 Xcode 垃圾 / 清理浏览器缓存」。
- 用户说「清理卸载残留 / 某个 app 删了还有残留」。
- 用户说「分析大文件 / 找重复文件 / 看看什么占空间」。

## 安全铁律（任何情况下不得违反）
1. **不删系统**：绝不触碰 /System、/usr、/bin、系统级受 SIP 保护的目录，以及用户文档/照片/邮件/iCloud 数据。
2. **先扫后清**：任何清理前必须先跑 scan.sh 预览，列出路径与预计释放空间。
3. **二次确认**：删除前必须把完整清单展示给用户，用户明确同意后才执行。clean_cache.sh 的 --execute 必须同时带 --yes 才真正删除，且对话层二次确认不可省略。
4. **分级备份**：应用残留（支持数据/容器/偏好）删除前强制备份到 ~/Documents/mac-clean-backup/<日期>/；缓存/日志/临时类不备份但必须列清单。
5. **最小授权**：仅在 purge 或系统级缓存清理时请求 sudo，绝不持久化密码。
6. **可撤销**：提供 restore <日期> 从备份恢复。
7. **受保护组件边界**：含 .BC.D_* 等被安全中心保护的可执行组件的 App 残留，skill 不强行备份/删除，交由用户在本地终端处理（见 references/safe_paths.md 第四节）。

## 使用流程
1. **扫描预览**：bash scripts/scan.sh --module all（或指定 memory / cache / residual）；加 --json 输出 JSON。
2. **展示清单**：把扫描结果整理成「类别 / 路径 / 体积 / 风险」表格给用户看。
3. **用户确认**：用户勾选要清理的项，再次复述将执行的动作。
4. **执行清理**：调用对应清理脚本，必要时先备份。
5. **输出报告**：清理前后体积对比 + 释放空间 + 恢复命令提示。

## 命令速查
| 动作 | 命令 |
|---|---|
| 只读扫描（全模块） | bash scripts/scan.sh --module all |
| 内存/磁盘/残留 扫描 | scan.sh --module memory\|cache\|residual（追加 --json） |
| 内存状态 + 高占用进程 | bash scripts/memory.sh [--top N] |
| 释放不活跃内存（purge） | bash scripts/memory.sh --purge（管理员授权，二次确认） |
| 磁盘垃圾预览/清理 | bash scripts/clean_cache.sh [--execute --yes] [--path <p> ...] [--include-tmp]（⚠ 执行前务必二次确认） |
| 卸载残留预览/清理 | bash scripts/clean_residual.sh --path <p> ... [--execute]（执行前自动备份） |
| 恢复误删残留 | bash scripts/restore.sh --list / restore.sh [--execute] <日期> |
| 大文件分析（只读报告） | bash scripts/analyze.sh --large [--min 100] [--top 30] [--path <dir> ...] |
| 重复文件分析（只读报告） | bash scripts/analyze.sh --dupes [--min-size 1] [--path <dir> ...] |
| 统一入口 | bash mac-clean.sh <子命令> ...（scan/memory/clean-cache/clean-residual/restore/analyze） |

## 功能模块
- **只读扫描 scan.sh**：内存 / 磁盘垃圾 / 卸载残留三类，支持 --json。
- **内存清理 memory.sh**：状态只读 + 高占用进程；--purge 经 macOS 管理员授权释放不活跃内存（不 kill 进程）。
- **磁盘垃圾 clean_cache.sh**：白名单、--execute --yes 才删、系统级走管理员。
- **卸载残留 clean_residual.sh**：指定路径、执行前自动备份（ditto）后删。
- **备份/恢复 restore.sh**：从 ~/Documents/mac-clean-backup/<日期>/ 恢复误删残留。
- **大文件/重复文件 analyze.sh**：只读报告，限定用户内容目录、绝不删除。

## 已知限制（重要）
1. scan 的孤儿探测是启发式，误报率很高（系统壁纸、已装 App 的缓存/容器都可能被标成「可能孤儿」）。**绝不能按扫描结果直接删**，必须逐条核对真实卸载状态（见 references/safe_paths.md 第三节）。
2. clean_cache.sh --execute 需显式 --yes 才真正删除；对话层二次确认仍不可省略。
3. 系统级清理与 purge 需本地管理员授权弹窗，无法在 WorkBuddy 内自动完成，需用户在本地终端执行。
4. ps 在部分沙箱/容器内被禁，内存模块的「高占用进程」列表可能为空——脚本已优雅降级提示，本机终端正常。
5. RAM 与磁盘空闲是两个概念：内存压力低不等于磁盘满；备份需要的是磁盘空闲（df -h）。
6. 含受保护可执行组件（如 .BC.D_*）的 App 残留无法在 WorkBuddy 内备份/删除，需用户在本地终端处理（见 references/safe_paths.md 第四节）。
