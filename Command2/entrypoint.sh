#!/bin/bash
set -e
IF_A=$(ip -4 addr show | grep "10.0.1." | awk '{print $NF}')
IF_B=$(ip -4 addr show | grep "10.0.2." | awk '{print $NF}')
echo "Interfaces: A=$IF_A, B=$IF_B"
[ -z "$IF_A" ] || tc qdisc add dev $IF_A root netem delay 200ms 20ms loss 5%
[ -z "$IF_B" ] || tc qdisc add dev $IF_B root netem delay 10ms
wg-quick up wg0
python3 /app/scripts/sdwan_monitor.py &
tail -f /dev/null
