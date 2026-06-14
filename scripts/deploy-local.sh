#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"          # 工作区根(4 仓父目录)
SYNC="$SCRIPT_DIR/sync-addresses.mjs"
RPC="http://127.0.0.1:8545"
NODE_PID=""        # 后台子 shell 的 pid(起链前用于早期失败拆链)
LISTEN_PID=""      # 真正监听 8545 的 hardhat node pid(就绪后解析,用于收尾/拆链)

log(){ printf '\033[1;34m[deploy-local]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[deploy-local] 错误:\033[0m %s\n' "$*" >&2; exit 1; }
# 杀真实监听进程(它退出会带走包裹它的子 shell);兜底再杀子 shell。
cleanup(){
  [ -n "$LISTEN_PID" ] && kill "$LISTEN_PID" 2>/dev/null || true
  [ -n "$NODE_PID" ] && kill "$NODE_PID" 2>/dev/null || true
}
trap 'code=$?; if [ "$code" -ne 0 ]; then log "失败(exit $code),拆除本地节点"; cleanup; fi' EXIT
trap 'die "用户中断"' INT

# 1) 预检:下游两仓 infrastructure 软链接在位
for repo in ScratchCard GreatLottoCore; do
  [ -e "$ROOT/$repo/node_modules/@greatlotto/infrastructure" ] \
    || die "$repo 缺 @greatlotto/infrastructure 软链接;在该仓跑 pnpm i 或 npm link @greatlotto/infrastructure"
done

# 2) 清三仓 chain-31337 旧部署(新链 ⇒ 旧 journal 会冲突)
for repo in infrastructure ScratchCard GreatLottoCore; do
  rm -rf "$ROOT/$repo/ignition/deployments/chain-31337"
done
log "已清理三仓 chain-31337 旧部署"

# 3) 起本地链(由 infrastructure 起,任一仓 hardhat node 都是同一条 31337)
log "启动 hardhat node..."
( cd "$ROOT/infrastructure" && npx hardhat node ) >"$SCRIPT_DIR/.hardhat-node.log" 2>&1 &
NODE_PID=$!
for i in $(seq 1 30); do
  if curl -s -X POST "$RPC" -H 'content-type: application/json' \
       --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -q '0x7a69'; then
    break
  fi
  sleep 1
  [ "$i" -eq 30 ] && die "hardhat node 30s 未就绪,见 $SCRIPT_DIR/.hardhat-node.log"
done
# npx → hardhat → node 多层,真正监听 8545 的是孙进程;解析其 pid 供收尾/拆链使用。
LISTEN_PID="$(lsof -i:8545 -sTCP:LISTEN -t 2>/dev/null | head -1)"
log "本地链就绪 (pid ${LISTEN_PID:-$NODE_PID}, chainId 31337)"

# 4) 部署 infrastructure
log "部署 infrastructure..."
( cd "$ROOT/infrastructure" && npx hardhat ignition deploy ignition/modules/infrastructure.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )

# 5) 同步 infra 地址 → ScratchCard/Core 的 localhost.json
node "$SYNC" --network localhost --write --only sc,core

# 6) 部署 ScratchCardLocal + GreatLottoCoreLocal
log "部署 ScratchCardLocal..."
( cd "$ROOT/ScratchCard" && npx hardhat ignition deploy ignition/modules/ScratchCardLocal.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )
log "部署 GreatLottoCoreLocal..."
( cd "$ROOT/GreatLottoCore" && npx hardhat ignition deploy ignition/modules/GreatLottoCoreLocal.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )

# 7) 同步三仓地址 → interface address.json[31337](含 MockEntropy)
node "$SYNC" --network localhost --write --only interface

# 7b) 同步三仓 ABI → interface(本地变体:GLC=GreatLottoCoinTest)
log "同步 ABI → interface..."
node "$SCRIPT_DIR/sync-abi.mjs" --network localhost --write

# 8) 收尾:节点保留运行(interface dev 需要)
STOP_PID="${LISTEN_PID:-$NODE_PID}"
log "完成 ✅  本地链保留运行 (pid $STOP_PID)"
log "停止本地链: kill $STOP_PID   (兜底: pkill -f 'hardhat node')"
trap - EXIT     # 正常结束不触发拆链
