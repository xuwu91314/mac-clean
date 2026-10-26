# mac-clean v2 功能规划

> 基于 v1.0.0（已在 WorkBuddy 平台提交审核）的实战复盘，规划第二版升级路线。
> 原则：保持 v1 的安全铁律（dry-run 默认、二次确认、备份可恢复、黑名单保护），把"受阻点"转化为"自动生成本地脚本"的能力。

---

## 一、v1 复盘：实战暴露的痛点

| # | 痛点 | 实战表现 |
|---|---|---|
| 1 | **受保护组件删不动** | 含 `.BC.D_*` 等安全组件的 App 残留，ditto 备份被安全中心拦截、删除也被拦，既备份不全也删不掉，只能交用户本地终端处理 |
| 2 | **系统级 + purge 需本地授权** | `/Library/Caches`、`/Library/Logs` 与 `sudo purge` 必须管理员密码窗，AI 无法代点 |
| 3 | **内存进程列表受限** | `ps` 在沙箱/容器内被禁，Top 进程列表无法在 AI 侧展示 |
| 4 | **dupes 扫描慢** | 依赖目录（`.venv`/`site-packages`）未充分排除时，几万库文件被扫入，哈希极慢甚至超时中断 |
| 5 | **孤儿误报率高** | 系统壁纸 `com.apple.wallpaper`、已装 App 缓存/容器被模糊匹配标成"可能孤儿"，需逐条人工核对 |
| 6 | **交互为一次性清单** | 删除前只给全量清单，缺"逐项勾选"能力 |
| 7 | **缺报告导出** | 扫描结果只能在终端看，无法落文件（HTML/Markdown）便于留档或分享 |

---

## 二、v2 目标

1. 把 v1 的三大"AI 删不动"场景（受保护组件 / 系统级 / purge）转为 **自动生成安全的本地一键脚本**，用户在终端跑即可，安全边界不变。
2. 补齐体验短板：卸载 App 全流程、交互式选择、dupes 提速、报告导出、定时清理。

---

## 三、功能升级清单（按优先级）

### P1（高价值 · 低风险 · 必做）

**1. 生成本地一键清理脚本（核心补强）**
- 新增 `scripts/generate_local_script.sh`：扫描到以下情形时**不强行在 AI 侧删**，而是生成一份带注释的本地 bash 脚本供用户终端执行：
  - 含 `.BC.D_*` 等受保护组件的卸载残留
  - 系统级路径（`/Library/Caches`、`/Library/Logs`）
  - 内存 `purge`
- 脚本内含：进程检查（`pgrep`）→ 备份（`ditto` 到备份目录）→ 删除（`rm -rf`）→ 恢复说明。
- 解决 v1 实战中 B 方案受阻、系统级/purge 受阻三大痛点。

**2. 卸载 App 全流程（AppCleaner 风格）**
- 新增 `scripts/uninstall_app.sh <App名>`：定位 `/Applications/*.app` + 所有关联目录（Application Support、Containers、Caches、偏好 `*.plist`、LaunchAgents/LaunchDaemons），先备份后删，避免"删了 App 还留一堆残留"。
- 用 bundle id 精确匹配，避免误删同名目录。

**3. 交互式选择清理项**
- `clean-residual` / `clean-cache` 清单展示后支持**编号选择**（如"清理 1,3,5"），而非全量执行，降低误删风险。

### P2（体验提升）

**4. dupes 性能优化**
- 并行哈希（`xargs -P` 或 Python `concurrent.futures`），大幅缩短大目录耗时。
- 排除清单默认生效并扩充：`.venv`/`venv`/`site-packages`/`dist`/`.tox`/`__pycache__`/`standalone-env`/`node_modules`/`.git`/`.Trash`/`Library/Caches`/`.cache`/`build`。
- 默认只扫用户指定目录，避免 `Movies`/`Music` 大媒体拖慢。

**5. 孤儿核对增强**
- `clean_residual.sh` 的启发式核对升级为：`mdfind "kMDItemCFBundleIdentifier == '<id>'"` 精确匹配 + `ls /Applications` 文件系统兜底 + 可选"逐条询问用户确认是否真卸载"。

**6. 报告导出**
- `scan` / `analyze` 新增 `--report <路径>`：生成 Markdown / HTML 报告文件，含可清理体积汇总、风险等级标注、各模块明细，便于留档。

### P3（锦上添花）

**7. 定时自动清理（launchd plist 模板）**
- 生成并指导安装每周自动清理缓存/日志的 `plist`（不含系统级/受保护项，安全优先）。

**8. 跨 macOS 版本兼容说明**
- 整理各命令在 macOS 12/13/14/15 的差异与回退逻辑。

**9. 多语言维护**
- v1 已补齐 `description_zh`/`description_en`，v2 稳定维护即可。

---

## 四、v2 技术改动点

| 文件 | 改动 |
|---|---|
| `scripts/generate_local_script.sh` | **新增**：根据扫描结果生成安全的本地清理脚本 |
| `scripts/uninstall_app.sh` | **新增**：AppCleaner 风格卸载 |
| `scripts/analyze.sh` | 重构：并行哈希 + 强化排除项 |
| `scripts/clean_residual.sh` | 重构孤儿核对（mdfind + ls 兜底 + 交互确认）+ 编号选择 |
| `scripts/clean_cache.sh` | 支持编号选择清理项 |
| `scripts/memory.sh` | `ps` 受限时更友好提示 + 引导用生成的本地脚本做 purge |
| `mac-clean.sh` | 入口新增 `uninstall-app`、`gen-script`、`report` 子命令 |
| `SKILL.md` | 增补 v2 触发词、新子命令、已知限制更新 |
| `references/safe_paths.md` | 补充"生成本地脚本"边界说明 |

---

## 五、风险评估

- 生成本地脚本仍依赖用户本地执行，**AI 不接触密码 / 不碰受保护文件**，安全边界与 v1 一致。
- AppCleaner 风格误删风险：必须 bundle id 精确匹配 + 二次确认 + 备份，缺一不可。
- 并行哈希不会改动任何文件（仅读取计算），只读阶段安全。

---

## 六、版本号建议

- `v1.0.0`（已发布 WorkBuddy 平台，含 scan/memory/clean-cache/clean-residual/restore/analyze）
- `v2.0.0`：新增 `uninstall-app` / `gen-script` / `report` 子命令 + 性能与交互优化；**向下兼容** v1 全部子命令，frontmatter 字段保持不变。
