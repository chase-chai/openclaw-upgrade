# openclaw-upgrade

在低配服务器（2C2G）上升级 OpenClaw 时，直接在服务器上运行 `npm install` 或编译会导致内存耗尽、服务器卡死。

本项目提供一个脚本，**在 Mac 本地用 Docker 完成编译，再将产物上传到服务器部署**，彻底绕开服务器内存瓶颈。

## 适用场景

- 服务器配置：2 核 2G 内存（或更低）
- 服务器系统：Ubuntu 22.04 x86_64
- 本地系统：macOS（需安装 Docker Desktop 和 Node.js）

## 原理

```
Mac 本地
  └─ Docker (ubuntu:22.04)
       └─ npm install openclaw@latest   <- 编译在本地完成
            └─ 打包 tar.gz
                 └─ scp 上传到服务器
                      └─ 解压 + 重启服务   <- 服务器只做部署
```

## 使用方法

### 1. 配置 SSH 别名（推荐）

在 `~/.ssh/config` 中添加：

```
Host myserver
    HostName 1.2.3.4
    User root
    Port 22
```

### 2. 下载脚本

```bash
curl -O https://raw.githubusercontent.com/chase-chai/openclaw-upgrade/main/openclaw-upgrade.sh
chmod +x openclaw-upgrade.sh
```

### 3. 执行升级

```bash
# 使用 SSH 别名
./openclaw-upgrade.sh myserver

# 或直接使用 IP
./openclaw-upgrade.sh root@1.2.3.4
```

脚本会自动完成：
1. 检查本地 Docker 是否运行
2. 获取服务器当前版本与 npm 最新版本
3. 在 Docker 容器内编译打包
4. 上传到服务器并重启服务

## 前置依赖

| 依赖 | 说明 |
|------|------|
| Docker Desktop | 在本地运行，用于编译 |
| Node.js / npm | 用于查询 npm 最新版本 |
| SSH 访问权限 | 能免密登录目标服务器 |

## 常见问题

**Q: 服务器系统不是 Ubuntu 22.04 可以用吗？**

不建议。编译环境与服务器系统不一致时，Node.js 二进制可能不兼容。

**Q: 升级失败了怎么办？**

脚本会自动备份旧版本。登录服务器后手动恢复：
```bash
cp -r /opt/openclaw.bak /opt/openclaw
openclaw gateway start
```

## License

MIT
