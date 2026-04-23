#!/bin/bash
set -e

# 1. Динамический поиск имен интерфейсов по IP
# Ищем, какой ethX владеет адресом из подсети 10.0.1.0/24
IFACE_A=$(ip -4 addr show | grep "10.0.1." | awk '{print $NF}')
# Ищем, какой ethX владеет адресом из подсети 10.0.2.0/24
IFACE_B=$(ip -4 addr show | grep "10.0.2." | awk '{print $NF}')

echo "SD-WAN: Channel A detected on $IFACE_A"
echo "SD-WAN: Channel B detected on $IFACE_B"

# 2. Применяем настройки к реальным интерфейсам, если они найдены
if [ -n "$IFACE_A" ]; then
    tc qdisc add dev "$IFACE_A" root netem delay 200ms 20ms loss 5%
else
    echo "Error: Channel A interface not found!"
fi

if [ -n "$IFACE_B" ]; then
    tc qdisc add dev "$IFACE_B" root netem delay 10ms
else
    echo "Error: Channel B interface not found!"
fi

# Далее запуск WireGuard и мониторинга...
wg-quick up wg0

tail -f /dev/null
