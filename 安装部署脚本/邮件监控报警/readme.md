#提前配置email配置文件
vim  /etc/mail.rc

set from=13568987281@163.com  #设置发件人邮箱地址
set smtp="smtp.163.com" 	#指定 SMTP 服务器地址
set smtp-port=25 #设置 SMTP 服务器的端口号
set smtp-auth-user="13568987281@163.com"   #设置登录 SMTP 服务器的用户名
set smtp-auth-password="LQUSV9i8XgEkpMPJ"  # 16位授权码，非登录密码！
set smtp-auth=login #指定认证方式为 login
set ssl-verify=ignore #忽略 SSL 证书验证


手动测试邮箱：echo "警告：端口异常 ---" | mailx -s "测试标题" 13522127643@163.com

# 创建脚本，如果脚本位置发生变化，那么也需要修改service_watcher.service的路径
vim  /usr/local/bin/service_watcher.sh
# 脚本加权
sudo chmod +x /usr/local/bin/service_watcher.sh

# 创建systemd服务
vim   /etc/systemd/system/service_watcher.service

# 重载systemd配置
sudo systemctl daemon-reload

# 启用开机自启
sudo systemctl enable service_watcher

# 启动服务
sudo systemctl start service_watcher

# 停止服务
sudo systemctl stop service_watcher

# 重启服务
sudo systemctl restart service_watcher

# 查看服务状态
sudo systemctl status service_watcher

# 查看日志
sudo tail -f /home/service_watcher/service_monitor.log

# 查看完整日志
sudo cat /home/service_watcher/service_monitor.log