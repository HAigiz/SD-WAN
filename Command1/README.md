Для начала делаем скрипт StrongSwan.sh исполняемым `chmod +x StrongSwan.sh`. После этого `docker compose up --build -d`

Проверим, что ping идет между филиалами для это `docker exec filial1 ping -c 3 192.168.100.2`

Теперь нужно узнать оптоволоконный интерфейс `docker exec filial1 iproute`(подсказка: IP-сети 10.0.1...)

Отрубаем этот интерфейс `docker exec -it filial1 tc qdisc change dev eth1 root netem loss 100%` (замените интерфейс)

Пробуем сделать ping `docker exec filial1 ping -c 3 192.168.100.2`. Видим, что нету связи между узлами - это минут подключения по IPsec, когда у нас нету автоматического переключения между интерфейсами и система только один привязанный интерфейс
