#!/bin/bash
if [ $# -lt 5 ]; then
  echo "Usage: $0 \${program} \${party} \${ip} \${port} \${interace} [\${kind}]"
  exit 1
fi
program=$1
party=$2
ip=$3
port=$4
interface=$5
kind=native
if [ $# -ge 6 ]; then
  kind=$6
fi
if [ "$party" = "2" ] && [ "$kind" != "native" ]; then
  echo "party 2 only supports native"
  exit 1
fi
if [ "$kind" != "native" ] && [ "$kind" != "wasm" ]; then
  echo "\$kind only supports native or wasm"
  exit 1
fi

curdir=$(pwd)

logdir=${curdir}/logs
mkdir -p ${logdir}
cfgfile=${curdir}/config/config
resfile=${curdir}/result-$party.csv
if [ ! -f "$resfile" ]; then
  echo "kind,name,bandwidth(Mbps),latency(ms),request_size(B),response_size(B),send_bytes(B),recv_bytes(B),cost(ms),memory(KB)" >$resfile
fi

CMD="./build/cpp/bench/bin/zktls_bench"
if [ "$kind" = "wasm" ]; then
  CMD="node ./browser/wasm/bench.js"
fi

./scripts/reset_network.sh $interface
for line in $(cat ${cfgfile}); do
  echo $line
  bandwidth=$(echo $line | awk -F: '{print $1}')
  delay=$(echo $line | awk -F: '{print $2}')
  request_size=$(echo $line | awk -F: '{print $3}')
  response_size=$(echo $line | awk -F: '{print $4}')
  echo "$bandwidth#$delay#$request_size#$response_size"
  logfile=${logdir}/bench-$kind-$program-$party-$bandwidth-$delay-$request_size-$response_size.log

  ./scripts/simulate_network.sh $interface $bandwidth $delay

  $CMD $program $party $ip $port $request_size $response_size >$logfile

  res=$(cat $logfile | grep DONE:)
  send_bytes=$(echo $res | awk -F'[:,"}]' '{for (i=1;i<NF;i++){if($i=="sendBytes") {print $(i+2)}}}')
  recv_bytes=$(echo $res | awk -F'[:,"}]' '{for (i=1;i<NF;i++){if($i=="recvBytes") {print $(i+2)}}}')
  total_cost=$(echo $res | awk -F'[:,"}]' '{for (i=1;i<NF;i++){if($i=="totalCost") {print $(i+2)}}}')
  memory=0
  if [ "$kind" == "native" ]; then
    memory=$(echo $res | awk -F'[:,"}]' '{for (i=1;i<NF;i++){if($i=="memory") {print int($(i+2) / 1024)}}}')
  fi

  if [ "$kind" == "wasm" ]; then
    memoryRes=$(cat $logfile | grep memStat)
    memory=$(echo $memoryRes | awk -F'[:,"}]' '{for (i=1;i<NF;i++){if($i=="totalJSHeapSize") {print int($(i+2) / 1024)}}}')
  fi

  echo "$kind,$program,$bandwidth,$delay,$request_size,$response_size,$send_bytes,$recv_bytes,$total_cost,$memory" >>$resfile
  sleep 4

  ./scripts/reset_network.sh $interface
  sleep 1
done
