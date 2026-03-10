#!/usr/bin/env bash
# ============================================================
# OpenClaw 远程升级脚本
# 在 Mac 本地运行，通过 Docker 编译后自动部署到 Linux 服务器
# 用法: ./openclaw-upgrade.sh <SSH别名或IP>
# 示例: ./openclaw-upgrade.sh myserver
#       ./openclaw-upgrade.sh 1.2.3.4
# ============================================================

set -euo pipefail

# ── 参数 ────────────────────────────────────────────────────
SSH_TARGET="${1:-}"
REMOTE_TMP="/tmp/openclaw-built.tar.gz"

# ── 颜色输出 ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ── 检查参数 ────────────────────────────────────────────────
[[ -z "$SSH_TARGET" ]] && error "用法: $0 <SSH别名或IP>  例如: $0 openclaw-xie"

# 直接复用 ~/.ssh/config 里的配置，不需要额外指定用户名和密钥
SSH_CMD="ssh -o ConnectTimeout=10 ${SSH_TARGET}"
SCP_CMD="scp -o ConnectTimeout=10"

echo ""
echo "🦞 OpenClaw 远程升级脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "目标服务器: ${SSH_TARGET}"
echo ""

# ── 检查 Mac 本地依赖 ───────────────────────────────────────
info "检查本地环境..."
command -v docker &>/dev/null || error "Docker 未安装，请先安装 Docker Desktop"
docker info &>/dev/null       || error "Docker 未运行，请先启动 Docker Desktop"
success "Docker 已就绪"

# ── 检查服务器连通性 ────────────────────────────────────────
info "检查服务器连接..."
$SSH_CMD "echo ok" &>/dev/null || error "无法连接服务器，请检查 SSH 别名配置: ssh ${SSH_TARGET}"
success "服务器连接正常"

# ── 获取服务器当前版本 ──────────────────────────────────────
info "获取服务器当前 OpenClaw 版本..."
CURRENT_VERSION=$($SSH_CMD "openclaw --version 2>/dev/null | head -1 || echo '未知'" || echo "未知")
info "当前版本: $CURRENT_VERSION"

# ── 获取 npm 最新版本号 ─────────────────────────────────────
info "查询 npm 最新版本..."
LATEST_VERSION=$(npm view openclaw version 2>/dev/null || echo "latest")
info "最新版本: $LATEST_VERSION"

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    warn "当前已是最新版本 ($LATEST_VERSION)，无需升级"
    echo "如需强制升级，请加 --force 参数: $0 ${SSH_TARGET} --force"
    exit 0
fi

echo ""
info "将从 $CURRENT_VERSION 升级到 $LATEST_VERSION"
echo ""

# ── 在 Docker 中编译 ────────────────────────────────────────
info "启动 x86_64 Linux 容器进行编译..."
info "（首次运行需要拉取镜像，约 100MB，请耐心等待）"
echo ""

CONTAINER_NAME="openclaw-builder-$$"

# 清理可能残留的容器
docker rm -f "$CONTAINER_NAME" &>/dev/null || true

docker run --platform linux/amd64 \
    --name "$CONTAINER_NAME" \
    --memory="2g" \
    ubuntu:22.04 \
    bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive

        echo "📦 安装 Node.js..."
        apt-get update -qq
        apt-get install -y -qq curl ca-certificates

        curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
        apt-get install -y -qq nodejs

        echo "Node.js 版本: $(node -v)"
        echo "npm 版本: $(npm -v)"

        echo ""
        echo "🦞 安装 OpenClaw..."
        SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm install -g openclaw@latest \
            --no-fund --no-audit

        echo ""
        OPENCLAW_BIN="$(npm bin -g)/openclaw"
        echo "✅ 安装完成，版本: $($OPENCLAW_BIN --version 2>/dev/null | head -1)"

        echo ""
        echo "📦 打包中..."
        NPM_ROOT=$(npm root -g)
        cd "$NPM_ROOT"
        tar -czf /openclaw-built.tar.gz openclaw
        echo "打包完成: $(du -sh /openclaw-built.tar.gz | cut -f1)"
    '

success "编译完成！"

# ── 从容器中取出包 ──────────────────────────────────────────
LOCAL_TMP=$(mktemp /tmp/openclaw-built-XXXXXX.tar.gz)
info "从容器中提取编译产物..."
docker cp "${CONTAINER_NAME}:/openclaw-built.tar.gz" "$LOCAL_TMP"
success "提取完成: $(du -sh "$LOCAL_TMP" | cut -f1)"

# 清理容器
docker rm -f "$CONTAINER_NAME" &>/dev/null || true

# ── 上传到服务器 ────────────────────────────────────────────
info "上传到服务器..."
$SCP_CMD "$LOCAL_TMP" "${SSH_TARGET}:${REMOTE_TMP}"
rm -f "$LOCAL_TMP"
success "上传完成"

# ── 服务器端部署 ────────────────────────────────────────────
info "在服务器上部署..."
$SSH_CMD bash <<'REMOTE_SCRIPT'
    set -e

    echo "🔍 探测 openclaw 安装路径..."
    NPM_ROOT=$(npm root -g 2>/dev/null || echo "")

    if [[ -z "$NPM_ROOT" ]]; then
        echo "❌ 无法获取 npm global root"
        exit 1
    fi

    echo "npm global root: $NPM_ROOT"

    # 停止服务
    echo "⏸ 停止 openclaw 服务..."
    openclaw gateway stop 2>/dev/null || true

    # 备份旧版本
    if [[ -d "$NPM_ROOT/openclaw" ]]; then
        echo "📦 备份旧版本..."
        mv "$NPM_ROOT/openclaw" "$NPM_ROOT/openclaw.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # 解压新版本
    echo "📂 解压新版本..."
    tar -xzf /tmp/openclaw-built.tar.gz -C "$NPM_ROOT/"
    rm -f /tmp/openclaw-built.tar.gz

    # 清理旧备份（只保留最近1个）
    ls -dt "$NPM_ROOT"/openclaw.bak.* 2>/dev/null | tail -n +2 | xargs rm -rf || true

    # 修复软链接
    echo "🔗 修复软链接..."
    OPENCLAW_MJS=$(find "$NPM_ROOT/openclaw/bin" -name "*.mjs" 2>/dev/null | head -1 || true)
    OPENCLAW_ENTRY=$(find "$NPM_ROOT/openclaw" -name "entry.js" 2>/dev/null | head -1 || true)
    if [[ -n "$OPENCLAW_MJS" ]]; then
        ln -sf "$OPENCLAW_MJS" /usr/bin/openclaw
        echo "软链接指向: $OPENCLAW_MJS"
    elif [[ -n "$OPENCLAW_ENTRY" ]]; then
        ln -sf "$OPENCLAW_ENTRY" /usr/bin/openclaw
        echo "软链接指向: $OPENCLAW_ENTRY"
    fi

    # 运行 doctor
    echo "🩺 运行 openclaw doctor..."
    openclaw doctor --non-interactive 2>/dev/null || true

    # 重启服务
    echo "🚀 重启 openclaw gateway..."
    openclaw gateway start 2>/dev/null || true

    echo ""
    echo "✅ 部署完成！"
    echo "当前版本: $(openclaw --version 2>/dev/null | head -1 || echo '未知')"
    openclaw gateway status 2>/dev/null || true
REMOTE_SCRIPT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "🦞 OpenClaw 升级完成！"
echo ""
