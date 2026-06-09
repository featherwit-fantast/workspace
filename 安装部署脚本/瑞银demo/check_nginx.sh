#!/bin/bash
nginx_pid=$(ps -ef |grep "nginx"|grep -v "sh$"|grep -v "grep"|awk '{print $2}')
nginx_pid_num=$( ps -ef |grep "nginx: master process"|grep -v "grep"|wc -l)

if [ $nginx_pid_num  -lt 1 ];then
   kill -9 $nginx_pid > /dev/null 2>&1
   exit 1  # 进程不存在直接失败
fi
