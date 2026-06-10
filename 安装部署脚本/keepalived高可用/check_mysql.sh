#!/bin/bash
mysql_pid=$(ps -ef |grep mysqld|grep -v "sh$"|grep -v "grep"|awk '{print $2}')
mysql_pid_num=$(netstat -tanlup|grep 3306|grep LISTEN|wc -l)

#当mysql不存在，则退出mysql，退出keepalived
if [ $mysql_pid_num  -lt 1 ];then
  kill -9 $mysql_pid > /dev/null 2>&1
  systemctl stop mysqld
  exit 1  # 进程不存在直接失败
fi