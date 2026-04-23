Начните с разрешения выполнения скрипта `chmod +x SD-WAN.sh` и запустите скрипт `bash SD-WAN.sh`

И запустите с помощью `docker compose up --build -d` 

Зайдите в filial1 и узнайте сетевой интерфейс, на котором сымитирован оптоволоконный канал `docker exec -it filial1 iproute`(подсказка: ip у этого канала 10.0.2.12)

После того, как узнали интерфейс отрубите данный канал
`docker exec -it filial1 tc qdisc change dev eth1 root netem loss 100%`(замените интерфейс)


После этого опять зайдите в контейнер и попробуйте сделать `ping 192.168.100.2`
`docker exec -it filial1 tc qdisc change dev eth1 root netem delay delay 10ms`(замените интерфейс)
