#!/bin/sh
set -e
# 定义常量
jdk_SOURCE="../jdk"
jdk_INSTALL_DIR="/usr/local/jdk"
PROFILE_FILE="/etc/profile"

# 卸载openjdk 包
if rpm -qa --qf '%{NAME}\n' | grep -E 'openjdk-'; thenrm
    echo "正在卸载旧版 openjdk ..."
    rpm -qa --qf '%{NAME}\n' | grep -E 'openjdk-' | xargs -r rpm -e --nodeps
fi

# 验证源目录存在
if [ ! -d "$jdk_SOURCE" ]; then
    echo "错误：openjdk 源目录不存在 $jdk_SOURCE" >&2
    exit 1
fi

# 清理旧安装目录
rm -rf "$jdk_INSTALL_DIR"

# 复制文件并保留权限
echo "安装 openjdk 到 $jdk_INSTALL_DIR ..."
cp -a "$jdk_SOURCE" "$jdk_INSTALL_DIR"

# 环境变量配置
grep -q "jdk_ROOT=$jdk_INSTALL_DIR" "$PROFILE_FILE" || {
    echo "export JAVA_HOME=$jdk_INSTALL_DIR" >> "$PROFILE_FILE"
    echo 'export PATH=$PATH:$JAVA_HOME/bin' >> "$PROFILE_FILE"
}
chmod -R  +x $jdk_INSTALL_DIR

# 立即生效
source /etc/profile

echo "安装完成！当前会话已生效。"
echo "提示：要使所有用户永久生效，请重新登录系统。"