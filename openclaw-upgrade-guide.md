# 在低配 Linux 服务器上升级 OpenClaw 的通用教程

> 适用场景：2C2G 等低配 Linux 服务器，直接执行官方升级脚本会导致服务器卡死/SSH 断连。
> 解决思路：在 Mac 本地用 Docker 编译，编译产物直接推送到服务器部署。

---

## 前置条件

| 条件 | 说明 |
|------|------|
| Mac 本地安装了 Docker Desktop | 且已启动 |
| Mac 本地安装了 Node.js / npm | 用于查询最新版本号 |
| SSH 别名已配置在 `~/.ssh/config` | 能用 `ssh <别名>` 直接连上服务器 |

---

## 第一步：配置 SSH 别名（已配置可跳过）

编辑 `~/.ssh/config`，添加你的服务器：

```
Host myserver              # ← 这里改成你喜欢的别名
    HostName 1.2.3.4       # ← 服务器 IP
    User root              # ← 登录用户名
    IdentityFile ~/.ssh/id_rsa  # ← SSH 私钥路径
```

验证是否配置成功：

```bash
ssh openclaw-xie   # 能登录即可
```

---

## 第二步：下载升级脚本

在 Mac 终端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/你的仓库/openclaw-upgrade.sh -o ~/openclaw-upgrade.sh
chmod +x ~/openclaw-upgrade.sh
```

> 或者直接把脚本文件保存到本地，`chmod +x` 赋予执行权限即可。

---

## 第三步：执行升级

```bash
bash openclaw-upgrade.sh <你的SSH别名>
```

例如：

```bash
bash openclaw-upgrade.sh myserver
```

脚本会自动完成以下所有步骤，**无需人工干预**：

```
1. 检查 Docker 是否运行
2. 检查服务器连接是否正常
3. 对比当前版本与最新版本（已是最新则自动退出）
4. 在 x86_64 Linux 容器内完整编译 OpenClaw
5. 打包编译产物并上传到服务器
6. 停止旧服务、备份旧版本、部署新版本
7. 修复软链接
8. 运行 openclaw doctor
9. 重启 openclaw gateway
```

---

## 升级过程示例输出

```
🦞 OpenClaw 远程升级脚本
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 目标服务器: openclaw-xie

[INFO] 检查本地环境...
[OK]   Docker 已就绪
[INFO] 检查服务器连接...
[OK]   服务器连接正常
[INFO] 当前版本: 2026.2.13
[INFO] 最新版本: 2026.3.8
[INFO] 将从 2026.2.13 升级到 2026.3.8

[INFO] 启动 x86_64 Linux 容器进行编译...
📦 安装 Node.js...
🦞 安装 OpenClaw...
✅ 安装完成，版本: 2026.3.8
📦 打包完成: 85M

[OK]   编译完成！
[INFO] 上传到服务器...
[OK]   上传完成
[INFO] 在服务器上部署...
⏸ 停止 openclaw 服务...
📦 备份旧版本...
📂 解压新版本...
🔗 修复软链接...
🩺 运行 openclaw doctor...
🚀 重启 openclaw gateway...
✅ 部署完成！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[OK]   🦞 OpenClaw 升级完成！
```

---

## 常见问题

**Q：首次运行很慢？**

正常现象。Docker 需要拉取 `ubuntu:22.04` 镜像（约 100MB），拉取完后会缓存，后续升级会快很多。

**Q：提示"当前已是最新版本"但我想强制重装？**

删除版本比较那段逻辑，或手动在服务器上执行：

```bash
openclaw --version  # 确认当前版本
```

然后等 npm 发布新版本后再跑脚本。

**Q：升级失败了怎么回滚？**

脚本会自动备份旧版本到 `openclaw.bak.时间戳` 目录，在服务器上执行：

```bash
# 找到备份目录
ls $(npm root -g)/openclaw.bak.*

# 恢复（把时间戳替换成实际的）
NPM_ROOT=$(npm root -g)
rm -rf $NPM_ROOT/openclaw
mv $NPM_ROOT/openclaw.bak.20260310120000 $NPM_ROOT/openclaw
openclaw gateway restart
```

**Q：为什么不直接在服务器上跑官方升级脚本？**

官方脚本会在服务器本地执行 `pnpm install` + `ui:build` + `build`，这个过程需要大量内存和磁盘 IO。2C2G 的服务器内存不足时会疯狂使用 Swap，导致磁盘 IO 打满，SSH 进程被饿死，表现为服务器卡死无法连接。

---

## 为什么这个方案可行

```
Mac 本地          Linux 服务器（2C2G）
      │                          │
      │  Docker x86_64 容器       │
      │  完整编译 OpenClaw         │
      │  打包 → tar.gz            │
      │                          │
      └──── scp 上传 ────────────→│
                                  │  解压 + 替换文件
                                  │  无需编译，零压力
                                  │  重启服务
```

服务器只负责解压和运行，所有编译压力都在 Mac 上完成。
