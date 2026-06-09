#!/bin/sh
set -e

# 定义常量
DOTNET_SOURCE="../dotnet"
DOTNET_INSTALL_DIR="/usr/local/dotnet"
PROFILE_FILE="/etc/profile"

# 卸载dotnet 包
if rpm -qa --qf '%{NAME}\n' | grep -E 'dotnet'; then
    echo "正在卸载旧版 dotnet ..."
    rpm -qa --qf '%{NAME}\n' | grep -E 'dotnet' | xargs -r rpm -e --nodeps
fi

# 验证源目录存在
if [ ! -d "$DOTNET_SOURCE" ]; then
    echo "错误：dotnet 源目录不存在 $DOTNET_SOURCE" >&2
    exit 1
fi

# 清理旧安装目录
rm -rf "$DOTNET_INSTALL_DIR"

# 复制文件并保留权限
echo "安装 dotnet 到 $DOTNET_INSTALL_DIR ..."
cp -a "$DOTNET_SOURCE" "$DOTNET_INSTALL_DIR"

# 环境变量配置
grep -q "DOTNET_ROOT=$DOTNET_INSTALL_DIR" "$PROFILE_FILE" || {
    echo "export DOTNET_ROOT=$DOTNET_INSTALL_DIR" >> "$PROFILE_FILE"
    echo 'export PATH=$PATH:$DOTNET_ROOT' >> "$PROFILE_FILE"
}

# 立即生效
chmod -R  +x $DOTNET_INSTALL_DIR
source   /etc/profile

echo "安装完成！当前会话已生效。"
echo "提示：要使所有用户永久生效，请重新登录系统。"