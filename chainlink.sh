#!/bin/bash

set -euo pipefail

readonly chainlink_node_address=${1:-}
readonly etherscan_api_key=${2:-}
readonly ethereum_node=${3:-}

total_reward="0"

get_eth_balance(){
  local addr=($1)
  ret=$(curl -s --data '{"jsonrpc":"2.0","id":2,"method":"eth_getBalance","params":["'$addr'","latest"]}' $ethereum_node)
  reward=$(echo $ret | jq -rc '.result')
  reward="${reward:2}"
  reward="${reward^^}"
  reward=$(bc <<< "obase=10; ibase=16; $reward")
  reward=$(bc -l <<< "$reward / 1000000000000000000")
  echo $reward
}

get_aggregator_reward(){
  local addr=($1)
  ret=$(curl -s --data '{"jsonrpc":"2.0","id":2,"method":"eth_call","params":[{"from":"0x0000000000000000000000000000000000000000","data":"0xe2e40317000000000000000000000000dc2d40327bdf2bd50e7777104822b44e2e496e93","to":"'$addr'"},"latest"]}' $ethereum_node)
  reward=$(echo $ret | jq -rc '.result')
  reward="${reward:2}"
  reward="${reward^^}"
  reward=$(bc <<< "obase=10; ibase=16; $reward")
  reward=$(bc -l <<< "$reward / 1000000000000000000")
  reward="${reward%000000000000000000}"
  echo $reward
}

get_oracle_reward(){
  local addr=($1)
  addr="${addr:2}"
  ret=$(curl -s --data '{"jsonrpc":"2.0","id":2,"method":"eth_call","params":[{"from":"0x0000000000000000000000000000000000000000","data":"0x70a08231000000000000000000000000'$addr'","to":"0x514910771AF9Ca656af840dff83E8264EcF986CA"},"latest"]}' $ethereum_node)
  reward=$(echo $ret | jq -rc '.result')
  reward="${reward:2}"
  reward="${reward^^}"
  reward=$(bc <<< "obase=10; ibase=16; $reward")
  reward=$(bc -l <<< "$reward / 1000000000000000000")
  reward="${reward%000000000000000000}"
  echo $reward
}

process_contract_info(){
  local dest=("$1")
  dest="${dest%\"}"
  dest="${dest#\"}"
  if [[ "$dest" == "" ]]; then
    return
  fi
  dest_info=$(curl -s 'https://api.etherscan.io/api?module=contract&action=getsourcecode&address='"$dest"'&apikey='"$etherscan_api_key")
  contract_name=$(echo $dest_info | jq -rc '.result[] | .ContractName')
  if [[ "$contract_name" == 'AccessControlledAggregator' ]]; then
    reward=$(get_aggregator_reward $dest)
    total_reward=$(echo $total_reward + $reward | bc)
    echo "  - $dest (AccessControlledAggregator): $reward LINK."
  elif [[ "$contract_name" == 'Oracle' ]]; then
    reward=$(get_oracle_reward $dest)
    total_reward=$(echo $total_reward + $reward | bc)
    echo "  - $dest (Oracle): $reward LINK."
  fi
}

date
echo "Node address: $chainlink_node_address."
eth_balance=$(get_eth_balance $chainlink_node_address)
echo "Node balance: $eth_balance ETH."
echo "Claimable rewards:"
res=$(curl -s 'https://api.etherscan.io/api?module=account&action=txlist&address='"$chainlink_node_address"'&startblock=0&endblock=99999999&sort=asc&apikey='"$etherscan_api_key")
for row in $(echo "$res" | jq -c '.result[] | .to' | sort | uniq);do
  process_contract_info $row
done

echo "We can claim a total amount of $total_reward LINK."
