#!/data/data/com.termux/files/usr/bin/bash
# ==========================================================
#  diplus-ops — BYD 车机哨兵监控运维栈 一键部署脚本
#  (Termux 环境, 参考原版 diplus-www 一键安装方式)
#
#  原项目: https://github.com/cnjackchen/diplus-www
#  本仓库: https://github.com/xch1986/diplus-ops
#
#  用法: 车机 Termux 直接执行:
#  bash <(curl -sSL https://raw.githubusercontent.com/xch1986/diplus-ops/main/install.sh)
# ==========================================================
PREFIX="/data/data/com.termux/files/usr"
home="$HOME"
tmp="$home/.diplus_install"
ZIP_URL="https://raw.githubusercontent.com/xch1986/diplus-ops/main/diplus-ops.zip"

echo ""
echo "=============================================="
echo " BYD 车机哨兵监控运维栈 (diplus-ops) 一键部署"
echo "=============================================="
echo " 将自动完成:"
echo "  1. 下载代码包 diplus-ops.zip 并解压"
echo "  2. 安装依赖 (nginx/php/sqlite/cronie/frp)"
echo "  3. 部署 web 服务到 ~/ (www/nginx/php/boot/frp)"
echo "  4. 初始化数据库并写入默认账号"
echo "  5. 启动 nginx + php-fpm + crond"
echo "  6. (可选) 安装 Magisk 保活模块 [需 root]"
echo ""

read -p "是否继续安装? (y/n): " choice
[ "$choice" != "y" ] && [ "$choice" != "Y" ] && { echo "已取消安装。"; exit 1; }

# ---------- 下载 ----------
echo ""
echo "[1/6] 下载代码包 ..."
mkdir -p "$tmp" && cd "$tmp"
rm -f diplus-ops.zip
curl -sSL "$ZIP_URL" -o diplus-ops.zip
if [ ! -s diplus-ops.zip ]; then
    echo "❌ 下载失败! 请检查网络 (GitHub 可能需要代理/科学上网)。"
    echo "   备选: 浏览器打开 $ZIP_URL 手动下载 diplus-ops.zip 放到 ~/ 后重跑本脚本"
    exit 1
fi
echo "   下载完成 ($(du -h diplus-ops.zip | cut -f1))"

echo "   解压 ..."
if ! unzip -o diplus-ops.zip > /dev/null 2>&1; then
    pkg install -y unzip > /dev/null 2>&1 || true
    unzip -o diplus-ops.zip > /dev/null || { echo "❌ 解压失败 (缺 unzip)"; exit 1; }
fi
[ -d diplus-ops ] || { echo "❌ 解压目录不存在"; exit 1; }
cd diplus-ops || exit 1

# ---------- 依赖 ----------
echo "[2/6] 安装依赖 ..."
for p in nginx php sqlite cronie; do
    if ! command -v "$p" > /dev/null 2>&1; then
        echo "   安装 $p ..."
        pkg install -y "$p" || echo "   ⚠ $p 安装失败 (可稍后手动: pkg install $p)"
    fi
done
if ! command -v frpc > /dev/null 2>&1; then
    echo "   安装 frp (提供 frpc) ..."
    pkg install -y frp || echo "   ⚠ frp 安装失败 (可稍后手动: pkg install frp)"
fi

# ---------- 部署 ----------
echo "[3/6] 部署文件到 ~/ ..."
cp -rf server/www "$home/www"
cp -rf server/nginx "$home/nginx"
cp -rf server/php "$home/php"
mkdir -p "$home/boot" "$home/frp" "$home/scripts"
cp -rf car/boot/. "$home/boot/" 2>/dev/null
cp -rf car/scripts/. "$home/scripts/" 2>/dev/null
[ -f "$home/frp/frpc.toml" ] || cp car/frpc.toml.example "$home/frp/frpc.toml"
cp car/crontab.root.txt "$home/crontab.root.txt"

# ---------- 数据库 ----------
echo "[4/6] 初始化数据库 ..."
mkdir -p "$home/db"
sqlite3 "$home/db/db.db" "CREATE TABLE IF NOT EXISTS settings(app TEXT, param TEXT, data TEXT); CREATE TABLE IF NOT EXISTS config(key TEXT PRIMARY KEY, value TEXT);" 2>/dev/null || true
sqlite3 "$home/db/db.db" "INSERT OR REPLACE INTO settings(app,param,data) VALUES('global','USER_ID','admin'); INSERT OR REPLACE INTO settings(app,param,data) VALUES('global','USER_PASSWORD','admin123'); INSERT OR REPLACE INTO config(key,value) VALUES('appOn','1');" 2>/dev/null || true
echo "   默认账号: admin / admin123 (登录后请立即修改)"

# ---------- 启动 ----------
echo "[5/6] 启动服务 ..."
# nginx (8018)
if [ ! -f "$PREFIX/tmp/nginx.pid" ] || ! kill -0 "$(cat "$PREFIX/tmp/nginx.pid" 2>/dev/null)" 2>/dev/null; then
    nginx -c "$home/nginx/nginx.conf" 2>/dev/null && echo "   nginx  : 8018 ✓" || echo "   ⚠ nginx 启动失败"
else
    echo "   nginx  : 已运行 ✓"
fi
# php-fpm (unix sock)
if ! pgrep -x php-fpm > /dev/null 2>&1; then
    php-fpm -y "$PREFIX/etc/php-fpm.conf" -D 2>/dev/null || php-fpm -D 2>/dev/null || echo "   ⚠ php-fpm 启动失败"
fi
pgrep -x php-fpm > /dev/null 2>&1 && echo "   php-fpm: ✓" || echo "   ⚠ php-fpm 未运行"
# crond (告警轮询)
if ! pgrep -x crond > /dev/null 2>&1; then
    crond 2>/dev/null || echo "   ⚠ crond 启动失败"
fi
# 用户 crontab: 告警轮询
grep alarm "$home/crontab.root.txt" > "$home/.cron_add" 2>/dev/null
crontab -l 2>/dev/null > "$home/.cron_all" || true
cat "$home/.cron_add" >> "$home/.cron_all"
sort -u "$home/.cron_all" | crontab - 2>/dev/null || true
rm -f "$home/.cron_add" "$home/.cron_all"

# ---------- Magisk 保活 (可选) ----------
echo "[6/6] Magisk 保活模块 [可选, 需 root] ..."
if command -v su > /dev/null 2>&1; then
    su -c "mkdir -p /data/adb/modules/diplus-keepalive && cp -rf $tmp/diplus-ops/car/magisk-module/. /data/adb/modules/diplus-keepalive/ && echo MAGISK_OK" 2>/dev/null | grep -q MAGISK_OK && echo "   Magisk 模块: 已安装 ✓" || echo "   ⚠ root 未授权, 跳过保活模块 (可稍后手动复制 car/magisk-module)"
    # root crontab: 守护保活
    grep daemon "$home/crontab.root.txt" > "$home/.cron_add" 2>/dev/null
    su -c "crontab -l 2>/dev/null > $home/.cron_all; cat $home/.cron_add >> $home/.cron_all; sort -u $home/.cron_all | crontab -; rm -f $home/.cron_add $home/.cron_all; echo CRON_OK" 2>/dev/null | grep -q CRON_OK && echo "   root 保活 crontab: 已写入 ✓" || echo "   ⚠ root crontab 写入失败 (跳过)"
else
    echo "   未检测到 root, 跳过保活模块 (仅局域网可访问)"
fi

# 清理
rm -rf "$tmp"

echo ""
echo "=============================================="
echo " ✅ 部署完成!"
echo "=============================================="
echo "  车机浏览器访问:  http://127.0.0.1:8018"
echo "  同网设备访问:    http://<车机IP>:8018"
echo "  Web 账号:        admin / admin123 (登录后请立即修改)"
echo ""
echo "  ⚠ 远程访问 (frp): 编辑 ~/frp/frpc.toml 填入你的 frps 服务器"
echo "    地址和 token, 然后执行: bash ~/boot/frpc.sh"
echo "    openlist / lucky 为第三方工具, 二进制需自行放置到 \$PREFIX/bin"
echo "    详细文档: https://github.com/xch1986/diplus-ops"
echo "  祝您用车愉快!"
echo ""
