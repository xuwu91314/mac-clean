# mac-clean 安全路径白名单与风险说明

本文件定义 `mac-clean` 可清理（白名单）与绝对禁止（黑名单）的路径，供 `scan.sh` 及各清理脚本统一引用。

## 一、可清理白名单（仅限列表内）

| 类别 | 路径 | 是否可再生 | 备份建议 |
|---|---|---|---|
| 用户缓存 | `~/Library/Caches/*` | 是 | 不备份（列清单） |
| 系统缓存 | `/Library/Caches/*`（需 sudo） | 是 | 不备份（列清单） |
| 用户日志 | `~/Library/Logs/*` | 是 | 不备份 |
| 系统日志 | `/Library/Logs/*`（需 sudo） | 是 | 不备份 |
| 诊断报告 | `~/Library/DiagnosticReports/*` | 是 | 不备份 |
| 临时文件 | `/tmp/*`、`/private/var/tmp/*` | 是 | 不备份 |
| 废纸篓 | `~/.Trash/*` | 已是回收站 | 不备份 |
| Xcode 派生数据 | `~/Library/Developer/Xcode/DerivedData/*` | 是（重编译再生） | 不备份 |
| Xcode 归档 | `~/Library/Developer/Xcode/Archives/*` | 否（历史归档） | 建议备份 |
| 浏览器缓存 | `~/Library/Caches/Google/Chrome` 等 | 是 | 不备份 |
| 邮件下载附件 | `~/Library/Containers/com.apple.mail/...` | 可重新下载 | 建议备份 |

**应用卸载残留（删除前强制备份）：**
- `~/Library/Application Support/<AppName>`
- `~/Library/Preferences/<com.xxx>.plist`
- `~/Library/Caches/<AppName>`
- `~/Library/Containers/<AppIdentifier>`
- `~/Library/LaunchAgents/<App>.plist`
- `/Library/LaunchAgents`、`/Library/LaunchDaemons`（需 sudo）

## 二、绝对禁止黑名单（任何情况下不碰）

- `/System`、`/System/Volumes`
- `/usr`、`/bin`、`/sbin`
- `/Library` 下的系统核心目录（除白名单明确列出的 Caches/Logs）
- 用户数据：`~/Documents`、`~/Desktop`、`~/Downloads`（仅大文件分析时只读报告，不删）
- `~/Pictures`、`~/Movies`、`~/Music`、`~/Photos`
- 邮件正文、通讯录、日历、钥匙串（`~/Library/Keychains`）
- iCloud 同步目录 `~/Library/Mobile Documents`
- 任何 SIP（System Integrity Protection）保护的路径

## 三、风险提示
- 删除应用缓存可能导致该应用首次启动变慢（属正常）。
- 孤儿探测为启发式（按目录名模糊匹配 .app），**误报率很高**——系统壁纸（`com.apple.wallpaper`）、已装 App 的缓存/容器（如仍在安装的第三方应用）都会被标成"可能孤儿"。**必须逐条核对真实卸载状态**：用 `mdfind "kMDItemCFBundleIdentifier == '<id>'"` 精确查 bundle id，并用 `ls /Applications` 做文件系统兜底，确认 App 真的不在后才算候选真残留。
- 系统级目录清理需要 sudo；若 SIP 阻止则优雅失败，不强行绕过。
- **区分 RAM 与磁盘**：`scan memory` 报的"空闲 64M"是内存（RAM）压力；备份需要的是**磁盘**空闲空间（`df -h`），二者不是一回事。

## 四、受保护文件 / 安全中心边界（实战补充）

> 实测发现：含受保护可执行/安全组件的 App 残留，无法在 WorkBuddy 内完成备份与删除，需用户在本地处理。

- **现象**：`clean_residual.sh` 在 `ditto` 备份某个含大型业务/安全组件的 App 残留（如某带 python 运行时与网关组件的 App）时，遇到一批 `.BC.D_*` 文件，被 WorkBuddy 安全中心规则判定为**受保护的可执行/安全组件**而拦截。
- **结果**：备份因此**不完整** → 脚本按"备份失败即中止删除"逻辑**不删原文件**（数据安全，未丢失）。备份目录虽显示体积，但残缺、不可用于恢复。
- **判定**：这类残留（含 `.BC.D_*`、带 python/网关等可执行组件）不是普通缓存残留，而是**业务/安全类 App**；在 WorkBuddy 沙箱 + 安全中心双重保护下，这些文件既备份不全、也删不掉。
- **处理规则（skill 边界）**：
  1. skill **不强行**备份/删除含 `.BC.D_*` 等被安全中心保护组件的 App 残留。
  2. 若用户确认 App 已卸载、确需清理，由用户在**本地终端**处理：先确认无相关进程在跑（必要时退出相关安全软件），再 `rm -rf` 对应目录。
  3. 因安全中心拦截而产生的**残缺备份**不可用于恢复，应在本地一并 `rm -rf` 清理。
  4. 任何被安全中心拦截的删除操作，遵守"不再重试"原则，改用本地处理。
- **脚本内确认（已补 v0.2）**：`clean_cache.sh` 的 `--execute` 必须同时指定 `--yes` 才真正删除，否则仅预览并报安全拦截。这作为对话层二次确认的双重防御；AI 仍须先把清单给用户、拿到明确同意后再带 `--yes` 调用。

## 五、分析模块范围与边界（只读报告）

> `analyze.sh` 用于发现"大文件"与"重复文件"，**只产出报告、绝不删除**。它是识别空间占用来源的工具，而非清理动作。

- **扫描范围（默认）**：仅用户内容目录 `~/Downloads`、`~/Documents`、`~/Desktop`、`~/Movies`、`~/Music`、`~/Pictures`。可用 `--path` 自定义。
- **排除项**：自动跳过 `node_modules/`、`.git/`、`.Trash/`、`Library/Caches/`、`.cache/`、`build/` 等开发依赖与系统缓存，避免把项目依赖、Git 对象误报为"可清理大文件/重复文件"造成误删风险或扫描卡顿。
- **大文件分析 `--large`**：按文件体积降序列出 ≥ `--min`（默认 100MB）的 Top N（默认 30）文件。仅帮助定位空间大户。
- **重复文件分析 `--dupes`**：先按体积分组（仅同体积才比对），再对同体积文件算 `sha256` 精确比对，输出重复组、每份体积与"删除重复副本可释放空间"。默认仅比对 ≥ `--min-size`（默认 1MB）的文件，控制哈希规模。
- **安全边界**：重复文件分析**只报告、不自动删**。删除任何重复副本前，必须让用户确认"保留哪一份"，因为两份内容相同不代表都无用（例如一处是源、一处是备份/导出）。清理动作仍须走对话层二次确认，不应直接将 dupes 结果交给自动删除。
- **性能**：`--dupes` 会对大文件做分块哈希，超大媒体库（数百 GB）可能耗时数分钟；可先用 `--min-size` 提高阈值缩小范围。
