# Модуль 3: Введение в SD-WAN
Проблемы традиционных WAN. Принципы SD-WAN (централизованное управление, overlay-сети, динамический выбор пути).


docker exec -it filial1 tc qdisc change dev eth1 root netem loss 100%

docker exec -it filial1 tc qdisc change dev eth1 root netem delay delay 10ms
