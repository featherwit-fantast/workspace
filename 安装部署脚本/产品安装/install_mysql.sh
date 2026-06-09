#!/bin/bash -x

echo "================================="
echo "===INSTALL MYSQL DEPENDENCIES===="
echo "================================="

rpm -Uvh --nodeps mysql-community-client-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-client-plugins-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-common-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-devel-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-embedded-compat-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-icu-data-files-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-libs-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-libs-compat-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-server-8.0.33-1.el7.x86_64.rpm
rpm -Uvh --nodeps mysql-community-server-debug-8.0.33-1.el7.x86_64.rpm
set +x

echo "================================="
echo "===INSTALL MYSQL DONE======="
echo "================================="