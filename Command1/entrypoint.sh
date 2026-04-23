#!/bin/bash
set -e

# 1. Настройка задержек (как обычно)
IF_A=$(ip -4 addr show | grep "10.0.1." | awk '{print $NF}')
IF_B=$(ip -4 addr show | grep "10.0.2." | awk '{print $NF}')
[ -z "$IF_A" ] || tc qdisc add dev $IF_A root netem delay 200ms
[ -z "$IF_B" ] || tc qdisc add dev $IF_B root netem delay 10ms

# 2. ДОБАВЛЯЕМ IP ТУННЕЛЯ (самое важное!)
# Мы вешаем IP туннеля на loopback, чтобы ядро его видело
if [ "$ROLE" = "filial1" ]; then
    ip addr add 192.168.100.1/32 dev lo
elif [ "$ROLE" = "filial2" ]; then
    ip addr add 192.168.100.2/32 dev lo
fi

# 3. Запуск демона StrongSwan
# В Alpine используется charon
/usr/lib/strongswan/charon & 
sleep 2

# 4. Загрузка конфигурации и запуск туннеля
swanctl --load-all
swanctl --initiate --child net-net

# 5. Якорь
tail -f /dev/null
