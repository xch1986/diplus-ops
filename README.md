# diplus-ops — BYD 车机哨兵监控运维栈

基于 **BYD DiLink 车机 + Termux + Magisk** 的车辆哨兵（远程监控 / 行驶数据 / 告警推送）自建运维系统。

本项目包含车机端完整代码：Web 前端（PHP + nginx + php-fpm）、Magisk 保活模块（守护链 v5.3）、frp 隧道配置模板、以及部署运维文档。**不含任何真实凭据与用户数据**（见文末「脱敏说明」）。

---

## 功能

| 模块 | 说明 |
|---|---|
| 哨兵视频 | 车辆晃动/振动自动录制（迪加 app 产生），Web 端按日期/事件筛选回放 |
| 行驶数据 | 充电统计、月里程、行程列表、趋势图（年度/日） |
| 告警推送 | 迪加 app 触发 → PHP 轮询 → 钉钉/企业微信机器人推送，含晃动/振动强度占位符 |
| 远程管理 | Web 设置页（阈值、消息模板、维护提醒）、OpenList 文件管理、Lucky 网络工具 |
| 保活守护 | Magisk 模块 + watchdog + daemon 双层守护，开机自启、进程抗杀、服务自愈 |

## 架构

```
┌─────────────┐   USB(记录仪/存储)   ┌──────────────────────────────┐
│  迪加 app   │◄────────────────────►│  /storage/emulated/0/vandiplus│
│ (哨兵录制)   │                      │  /storage/85D5-14FD (SD)      │
└──────┬──────┘                      └──────────────┬───────────────┘
       │ 8988 数据口                                  │
┌──────▼─────────────────────────────────────────────▼───────────────┐
│ BYD DiLink 车机 (DiLink 13.6, root: Magisk)                         │
│  Termux:                                                           │
│    nginx(8018) + php-fpm  → www/  (PHP 前端 + API)                 │
│    openlist(5244)          → 文件管理                              │
│    lucky(16601)            → 网络工具                              │
│    frpc                    → frp 隧道(公网访问)                    │
│    crond                   → 每分钟告警轮询 + 守护保活              │
│  Magisk 模块 diplus-keepalive:                                     │
│    service.sh(开机) → watchdog(60s) → daemon(30s) → 各服务自愈      │
└──────────────┬─────────────────────────────────────────────────────┘
               │ frp (tcp 隧道)
        ┌──────▼──────┐
        │  frps 服务器 │──► 公网访问: www / openlist / lucky / ssh
        └─────────────┘
```

## 目录结构

```
diplus-ops/
├── README.md
├── docs/
│   ├── architecture.md      # 架构与网络拓扑详解
│   ├── ops-guide.md         # 运维指南（远程操作/常见故障/防复发机制）
│   └── api.md               # Web API 清单
├── car/                     # 车机端
│   ├── magisk-module/       # Magisk 保活模块
│   │   ├── module.prop
│   │   ├── service.sh       # 开机入口
│   │   ├── diplus-watchdog.sh  # 看门狗 v2 (60s)
│   │   └── diplus-daemon.sh    # 守护 daemon v5.3 (30s 自愈循环)
│   ├── boot/                # Termux 开机脚本（frpc/openlist/lucky/配置监听）
│   ├── scripts/             # start_daemon / boot_diag / patch 脚本
│   ├── frpc.toml.example    # frp 隧道配置模板（脱敏）
│   └── crontab.root.txt     # root crontab（告警轮询 + 守护保活）
└── server/                  # Termux 服务端
    ├── www/                 # PHP Web 全套（index/settings/video_list/sum/api/…）
    ├── nginx/               # nginx 配置
    └── php/                 # php.ini
```

## 一键部署（推荐）

在车机 **Termux** 中直接执行（参考原版 diplus-www 的一键安装方式）：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/xch1986/diplus-ops/main/install.sh)
```

脚本自动完成：

1. 下载代码包 `diplus-ops.zip` 并解压
2. 安装依赖（nginx / php / sqlite / cronie / frp）
3. 部署 web 服务到 `~/`（www / nginx / php / boot / frp）
4. 初始化数据库（Web 登录账号由安装脚本交互式设置，**仓库不含任何真实凭据**）
5. 启动 nginx + php-fpm + crond（含告警轮询 crontab）
6. 检测到 root 时自动安装 Magisk 保活模块 + 守护 crontab

> `openlist` / `lucky` 为第三方工具，二进制需自行放置到 `$PREFIX/bin`，脚本会检测并提示。

## 快速开始（手动部署）

### 前置

- BYD DiLink 车机（或任意 Android）已 root（Magisk）
- Termux 已安装并配置：nginx、php-fpm、frpc、openlist、lucky、crond
- 一台 frps 服务器（或使用自建 frp）

### 部署

1. **安装服务端**（Termux home）：

```bash
# 将 server/ 下内容放入 Termux home
cp -r www nginx php $HOME/
# 启动 nginx + php-fpm
nginx -c $HOME/nginx/nginx.conf
php-fpm -y $PREFIX/etc/php-fpm.conf -D --allow-to-run-as-root
```

2. **配置 frp 隧道**：

```bash
cp frpc.toml.example $HOME/frp/frpc.toml
# 编辑：填入你的 frps 地址与 token
bash $HOME/boot/frpc.sh
```

3. **安装 Magisk 保活模块**：

```bash
# 将 car/magisk-module/ 打包为 zip 后在 Magisk 中刷入，或直接放入
cp -r magisk-module /data/adb/modules/diplus-keepalive/
# 手动验证
sh /data/local/tmp/start_daemon.sh
```

4. **配置 crontab**（root，参考 `car/crontab.root.txt`）：

```
* * * * * curl -sk -m 20 http://127.0.0.1:8018/api/alarm_poll.php?mins=3 >/dev/null 2>&1
* * * * * kill -0 $(cat /data/local/tmp/diplus-daemon.pid) 2>/dev/null || sh /data/local/tmp/start_daemon.sh
```

5. **初始化数据库**：`db/db.db`（SQLite）含 `config` 表（key/value）与各业务表，由 `www/api/*.php` 自动建表（或按 api.md 中的初始化接口执行）。

### 远程访问

| 服务 | 端口(车机) | 说明 |
|---|---|---|
| diplus Web | 8018 | 主页面：哨兵视频/行驶数据/设置 |
| OpenList | 5244 | 文件管理 |
| Lucky | 16601 | 网络工具 |
| sshd | 8022 | SSH 登录 |

公网访问通过 frp 隧道映射，见 `frpc.toml.example`。

## 防复发机制（守护链 v5.3）

> 项目历史中反复出现「失联」：Termux 被禁用、进程被杀、内部存储视图损坏、SD 掉挂载、下电后不恢复。v5.3 为此设计了多层自愈：

- **service.sh（开机）**：延迟 20s 确保 Termux 未被禁用（`pm enable com.termux`）→ 拉起 watchdog
- **watchdog（60s）**：检查 daemon 是否存活，死了拉起；对 daemon 与自身设置 `oom_score_adj=-1000` + `nice -20` 抗杀
- **daemon（30s 循环）**：
  - nginx / php-fpm / frpc / openlist / lucky / crond 任一不在 → 拉起
  - php-fpm 502 → 重建
  - 8988 迪加数据口 → 恢复 app 服务（带 300s 冷却）
  - 内部存储 fuse 自愈 v3：开机 240s 宽限（避免干扰系统启动导致中控黑屏）→ SELinux 放行 → `sm mount emulated` → bind 完整视图（120s 冷却）
  - SD 恢复：USB host 模式重上电 → USB/SCSI 重扫（**不重启 vold**，避免打断内部存储 + 中控黑屏）（300s 冷却）

详见 [docs/ops-guide.md](docs/ops-guide.md)「防复发机制」章节。

## 安全与脱敏说明

本仓库为**公开存档/交接用途**，已做如下处理：

- ❌ 不含：frps token、隧道公网地址、Web 登录口令、企业微信/钉钉 webhook、JWT 密钥、SQLite 业务数据（db.db）、Lucky/OpenList 真实配置
- ❌ 不含：UFI-TOOLS（第三方开源项目，见 [github.com/kanoqwq/UFI-TOOLS](https://github.com/kanoqwq/UFI-TOOLS)）——车机远程通道依赖的 UFI 设备工具不在本项目范围内
- ✅ 提供：`frpc.toml.example`（脱敏模板）、全部业务代码与守护脚本、运维文档

如你有自己的部署实例，请勿直接使用示例凭据；所有密码/token 请自行生成。

## License

MIT
