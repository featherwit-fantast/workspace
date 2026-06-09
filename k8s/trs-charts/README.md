# TRS Charts 独立部署指南

## 概述

TRS应用已完全拆分为独立的Helm charts，每个服务对应一个独立的chart。这种架构提供了：

- ✅ **完全独立**: 每个服务可以独立部署、升级和管理
- ✅ **灵活版本管理**: 每个服务有自己的版本号和镜像tag
- ✅ **精确回滚**: 可以单独回滚某个服务
- ✅ **配置独立**: 每个服务的配置完全独立，无依赖关系

## 目录结构

```
trs-charts/
├── client-ui/              # 客户端UI服务
├── trader-ui/              # 交易员UI服务
├── otc-ui/                 # OTC UI服务
├── calc/                   # 计算服务
├── client/                 # 客户端后端服务
├── hedge/                  # 对冲服务
├── otc/                    # OTC后端服务
├── rtc/                    # 实时通信服务
├── sso/                    # 单点登录服务
└── sync/                   # 同步服务
```

每个服务包含：
- Chart.yaml - Chart 元数据
- values.yaml - 完整的配置（数据库、Redis、Kafka等）
- templates/ - Kubernetes 资源模板

## 可用服务

### UI 服务
- `client-ui` - 客户端 UI
- `trader-ui` - 交易员 UI
- `otc-ui` - OTC UI

### 后端服务
- `calc` - 计算引擎
- `client` - 客户端后端
- `hedge` - 对冲服务
- `otc` - OTC 服务
- `rtc` - RTC 服务
- `sso` - 单点登录
- `sync` - 同步服务

## 部署方式

### 部署单个服务

```bash
# 部署 client-ui
cd trs-charts/client-ui
helm install client-ui . -n onederiv-test

# 部署 sso 服务
cd trs-charts/sso
helm install sso . -n onederiv-test

# 部署其他服务类似
```

### 批量部署多个服务

```bash
#!/bin/bash
SERVICES="client-ui trader-ui client sso calc"
NAMESPACE="onederiv-test"

for svc in $SERVICES; do
  echo "部署 $svc..."
  helm upgrade --install $svc ./trs-charts/$svc -n $NAMESPACE
done
```

### 更新服务

```bash
# 更新镜像版本
cd trs-charts/client
helm upgrade client . -n onederiv-test --set image.tag=1.4

# 或修改 values.yaml 后升级
helm upgrade client . -n onederiv-test
```

### 卸载服务

```bash
helm uninstall client -n onederiv-test
```

## 配置管理

每个服务的 values.yaml 包含完整配置：

```yaml
# 示例: client/values.yaml
namespace: onederiv-test
replicaCount: 1

image:
  repository: devops-docker-bkrepo.glmszq.com/w283fd/docker-local
  name: client
  tag: "1.3"

db:
  mysql:
    host: 172.28.30.52
    port: 2883
    username: onederiv@OneDeriv#wx_dtpp_test
    password: Onederiv@2026

redis:
  host: 172.28.112.246
  port: 6379
  password: GLms@527

kafka:
  bootstrapServers: "172.28.112.55:9092,..."
```

修改配置后重新部署即可生效。

## 验证部署

```bash
# 查看所有服务
kubectl get pods -n onederiv-test
kubectl get svc -n onederiv-test

# 查看特定服务
kubectl get pods -n onederiv-test -l app=client
kubectl logs -n onederiv-test -l app=client --tail=100

# 查看镜像版本
kubectl get pods -n onederiv-test \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
```

## 回滚操作

```bash
# 查看历史
helm history client -n onederiv-test

# 回滚到上一版本
helm rollback client -n onederiv-test

# 回滚到指定版本
helm rollback client 2 -n onederiv-test
```

## CI/CD 集成示例

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    parameters {
        choice(name: 'SERVICE', choices: ['client-ui', 'client', 'sso', 'calc'])
        string(name: 'IMAGE_TAG', defaultValue: '1.3')
    }
    stages {
        stage('Deploy') {
            steps {
                sh """
                    cd trs-charts/${params.SERVICE}
                    helm upgrade --install ${params.SERVICE} . \
                        --namespace onederiv-test \
                        --set image.tag=${params.IMAGE_TAG}
                """
            }
        }
    }
}
```

## 最佳实践

1. **版本管理**: 为每个服务维护独立的版本号
2. **配置分离**: 敏感信息使用 Kubernetes Secrets
3. **资源限制**: 确保每个服务都设置了合理的资源限制
4. **健康检查**: 为关键服务添加 liveness 和 readiness 探针
5. **日志管理**: 配置日志轮转和集中收集

## 故障排查

### 部署前注意事项

1. 确保目标命名空间已创建
2. 确保 imagePullSecrets 已配置
3. 后端服务需要数据库、Redis、Kafka 可访问
4. UI 服务需要配置正确的 Ingress 域名

### 镜像拉取失败

```bash
# 检查 imagePullSecrets
kubectl get secret docker-repo-token -n onederiv-test

# 创建 secret
kubectl create secret docker-registry docker-repo-token \
  --docker-server=devops-docker-bkrepo.glmszq.com \
  --docker-username=<username> \
  --docker-password=<password> \
  -n onederiv-test
```

### ConfigMap 未找到

确保服务的 templates 目录中有 configmap.yaml 文件。

### Pod 启动失败

```bash
# 查看 Pod 详情
kubectl describe pod <pod-name> -n onederiv-test

# 查看日志
kubectl logs <pod-name> -n onederiv-test
```

## 总结

所有 TRS charts 现已完全独立，可以单独部署和管理，无需任何 umbrella chart 依赖。每个服务包含完整的配置，可以灵活地进行版本控制和部署。
