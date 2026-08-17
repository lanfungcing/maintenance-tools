#!/bin/bash
set -euo pipefail

# ================= 参数校验 =================
if [ $# -lt 1 ]; then
    echo "[ERROR] 用法: $0 <formula-name> [formula-name ...]"
    echo ""
    echo "示例:"
    echo "  $0 avro-tools"
    echo "  $0 avro-tools dolt ffmpeg"
    echo ""
    echo "说明: 本地并行 rebuild 指定的 Formula，代替流水线上的 create-rebuild-pr workflow。"
    echo "      每个 formula 在独立的 ci-runner 容器中执行："
    echo "      删 bottle 块 → 建分支 → push 个人 fork → 创建 PR。"
    echo ""
    echo "环境变量:"
    echo "  ATOMGIT_TOKEN / ATOMGIT_USER / ATOMGIT_EMAIL  必填"
    echo "  MAX_PARALLEL  并发数（默认 8）"
    exit 1
fi

FORMULAS=("$@")
MAX_PARALLEL="${MAX_PARALLEL:-8}"
LOG_DIR="rebuild-logs"

echo "[INFO] 目标 Formula (${#FORMULAS[@]} 个): ${FORMULAS[*]}"
echo "[INFO] 并发数: ${MAX_PARALLEL}"

# ================= 环境变量校验 =================
for var in ATOMGIT_TOKEN ATOMGIT_USER ATOMGIT_EMAIL; do
    if [ -z "${!var}" ]; then
        echo "[ERROR] 环境变量 $var 未设置"
        exit 1
    fi
done

# 导出给 xargs 子进程使用
export ATOMGIT_TOKEN ATOMGIT_USER ATOMGIT_EMAIL
export WORKDIR="$PWD"
export LOG_DIR

mkdir -p "$LOG_DIR"

# ================= 拉取最新 ci-runner 镜像 =================
echo "[INFO] 拉取最新 ci-runner 镜像..."
docker pull swr.cn-north-4.myhuaweicloud.com/harmonybrew/ci-runner:latest

# ================= 并行 rebuild =================
echo "[INFO] 开始并行 rebuild..."
set +e
printf '%s\n' "${FORMULAS[@]}" | xargs -P "$MAX_PARALLEL" -n 1 bash -c '
    formula="$1"
    log="$LOG_DIR/rebuild-${formula}.log"
    if docker run --rm \
        -v "$WORKDIR":/workdir -w /workdir \
        -e ATOMGIT_TOKEN -e ATOMGIT_USER -e ATOMGIT_EMAIL \
        swr.cn-north-4.myhuaweicloud.com/harmonybrew/ci-runner:latest \
        python3 create-rebuild-pr.py "$formula" > "$log" 2>&1; then
        echo "[OK]   $formula"
    else
        echo "[FAIL] $formula (日志: $log)"
        exit 1
    fi
' _
rc=$?
set -e

# ================= 汇总 =================
if [ "$rc" -eq 0 ]; then
    echo "[OK] 全部 rebuild 完成"
else
    echo "[WARN] 部分 rebuild 失败，请查看 $LOG_DIR/"
    exit 1
fi
