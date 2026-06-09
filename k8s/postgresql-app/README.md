#注：
#项目部署使用本地镜像，需要先将 postgresql镜像上传至本地仓库，并且修改values.yaml配置文件的镜像地址
#项目基于k8s-1.20版本开发测试，1.24及之后版本需要重新定制
#项目pvc基于本地存储创建，启动前需要确认本地存储目录是否正确

部署步骤
1，上传postgresql镜像至本地仓库（示例）
导入镜像：docker load -i postgres.tar
修改镜像名称：docker tag postgres:latest   192.168.100.12:5000/postgres:latest
将镜像上传至仓库：docker push 192.168.100.12:5000/postgres:latest

2，节点创建本地存储目录
sudo mkdir -p /mnt/data/{postgres,backups}
sudo chmod 777 /mnt/data/{postgres,backups}

2，解压文件并修改values.yaml文件镜像地址
解压：tar xf   postgresql-app.tar.gz
修改镜像路径：sed -i 's|192.168.100.12:5000/postgres:latest|xxxxxx|g'  values.yaml

3，执行helm，安装Chart（注意路径，namespace自定义）
helm install postgresql-app  ./postgresql-app -n pg-ns --create-namespace

4，检查服务
查询容器状态：kubectl get pod -A -owide |  grep  pg-ns
登陆容器：kubectl exec -it postgres-8595c67bfd-gn5v5 -n pg-ns sh
登陆数据库：psql -U postgres -d postgres
查询数据表数据数量：SELECT count(*)   FROM test;
本地目录查询备份数据：ll  /mnt/data/backups

