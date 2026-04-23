#! /bin/bash

PRIVATE_KEY_FILIAL1=$(wg genkey)
PUBLIC_KEY_FILIAL1=$(echo "$PRIVATE_KEY_FILIAL1" | wg pubkey)

PRIVATE_KEY_FILIAL2=$(wg genkey)
PUBLIC_KEY_FILIAL2=$(echo "$PRIVATE_KEY_FILIAL2" | wg pubkey)

mkdir -p filial1/scripts
mkdir -p filial2/scripts

cat > filial1/wg0.conf << EOF
[Interface]
Address = 192.168.100.1/30
PrivateKey = $PRIVATE_KEY_FILIAL1
ListenPort = 51820

# Туннель через канал A (eth1)
[Peer]
PublicKey = $PUBLIC_KEY_FILIAL2
Endpoint = 10.0.1.12:51820
AllowedIPs = 192.168.200.0/24

# Туннель через канал B (eth2)
[Peer]
PublicKey = $PUBLIC_KEY_FILIAL2
Endpoint = 10.0.2.12:51820
AllowedIPs = 192.168.100.0/24
EOF

cat > filial2/wg0.conf << EOF
[Interface]
Address = 192.168.100.2/30
PrivateKey = $PRIVATE_KEY_FILIAL2
ListenPort = 51820

[Peer]
PublicKey = $PUBLIC_KEY_FILIAL1
Endpoint = 10.0.1.11:51820
AllowedIPs = 192.168.100.0/24

[Peer]
PublicKey = $PUBLIC_KEY_FILIAL1
Endpoint = 10.0.2.11:51820
AllowedIPs = 192.168.100.0/24
EOF

cat > filial1/scripts/sdwan_monitor.py << EOF
#!/usr/bin/env python3
import os
import re
import time
import subprocess
from collections import deque

WG_INTERFACE = os.getenv("WG_INTERFACE", "wg0")
WG_PEER_PUBKEY = os.environ["WG_PEER_PUBKEY"]

# Underlay endpoint'ы удаленной стороны
ENDPOINT_A = os.getenv("ENDPOINT_A", "10.0.1.12:51820")
ENDPOINT_B = os.getenv("ENDPOINT_B", "10.0.2.12:51820")

# Кого пингуем для измерения задержки (обычно IP без порта)
PING_A = ENDPOINT_A.split(":")[0]
PING_B = ENDPOINT_B.split(":")[0]

# Тюнинг
PING_COUNT = int(os.getenv("PING_COUNT", "3"))
PING_TIMEOUT = int(os.getenv("PING_TIMEOUT", "1"))
INTERVAL_SEC = float(os.getenv("INTERVAL_SEC", "3"))
LOSS_THRESHOLD = float(os.getenv("LOSS_THRESHOLD", "20"))      # %
SWITCH_DELTA_MS = float(os.getenv("SWITCH_DELTA_MS", "8"))     # гистерезис
STICKY_MIN_SEC = float(os.getenv("STICKY_MIN_SEC", "15"))      # hold-down
WINDOW = int(os.getenv("WINDOW", "5"))                         # окно сглаживания

rtt_re = re.compile(r"rtt min/avg/max/(?:mdev|stddev) = [\d\.]+/([\d\.]+)/")
loss_re = re.compile(r"(\d+(?:\.\d+)?)% packet loss")


def ping_stats(host: str):
    cmd = ["ping", "-c", str(PING_COUNT), "-W", str(PING_TIMEOUT), host]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")

    loss = 100.0
    avg = 9999.0

    m_loss = loss_re.search(out)
    if m_loss:
        loss = float(m_loss.group(1))

    m_rtt = rtt_re.search(out)
    if m_rtt:
        avg = float(m_rtt.group(1))

    return avg, loss


def set_endpoint(endpoint: str):
    subprocess.run(
        ["wg", "set", WG_INTERFACE, "peer", WG_PEER_PUBKEY, "endpoint", endpoint],
        check=False,
    )


def score(rtt, loss):
    # штраф за потери, чтобы "чистый" канал выигрывал при близком RTT
    return rtt + (loss * 5.0)


def main():
    hist_a = deque(maxlen=WINDOW)
    hist_b = deque(maxlen=WINDOW)

    current = None
    last_switch = 0.0

    while True:
        rtt_a, loss_a = ping_stats(PING_A)
        rtt_b, loss_b = ping_stats(PING_B)

        hist_a.append((rtt_a, loss_a))
        hist_b.append((rtt_b, loss_b))

        avg_rtt_a = sum(x[0] for x in hist_a) / len(hist_a)
        avg_loss_a = sum(x[1] for x in hist_a) / len(hist_a)
        avg_rtt_b = sum(x[0] for x in hist_b) / len(hist_b)
        avg_loss_b = sum(x[1] for x in hist_b) / len(hist_b)

        a_ok = avg_loss_a <= LOSS_THRESHOLD
        b_ok = avg_loss_b <= LOSS_THRESHOLD

        best = None
        if a_ok and b_ok:
            # основной критерий — задержка (с учетом небольшого штрафа за loss)
            s_a = score(avg_rtt_a, avg_loss_a)
            s_b = score(avg_rtt_b, avg_loss_b)
            best = "A" if s_a <= s_b else "B"
        elif a_ok:
            best = "A"
        elif b_ok:
            best = "B"

        now = time.time()

        print(
            f"A: rtt={avg_rtt_a:.1f}ms loss={avg_loss_a:.1f}% | "
            f"B: rtt={avg_rtt_b:.1f}ms loss={avg_loss_b:.1f}% | current={current}"
        )

        if best is None:
            print("No healthy channel")
        else:
            target_endpoint = ENDPOINT_A if best == "A" else ENDPOINT_B

            if current is None:
                set_endpoint(target_endpoint)
                current = best
                last_switch = now
                print(f"Initial channel -> {best} ({target_endpoint})")
            elif current != best:
                # антифлаппинг: переключаемся только если реально лучше и не слишком часто
                cur_rtt = avg_rtt_a if current == "A" else avg_rtt_b
                new_rtt = avg_rtt_a if best == "A" else avg_rtt_b
                improved = (cur_rtt - new_rtt) >= SWITCH_DELTA_MS
                sticky_ok = (now - last_switch) >= STICKY_MIN_SEC

                if improved and sticky_ok:
                    set_endpoint(target_endpoint)
                    current = best
                    last_switch = now
                    print(f"Switched -> {best} ({target_endpoint})")

        time.sleep(INTERVAL_SEC)


if __name__ == "__main__":
    main()
EOF

cat > filial2/scripts/sdwan_monitor.py << EOF
#!/usr/bin/env python3
import os
import re
import time
import subprocess
from collections import deque

WG_INTERFACE = os.getenv("WG_INTERFACE", "wg0")
WG_PEER_PUBKEY = os.environ["WG_PEER_PUBKEY"]

# Underlay endpoint'ы удаленной стороны
ENDPOINT_A = os.getenv("ENDPOINT_A", "10.0.1.11:51820")
ENDPOINT_B = os.getenv("ENDPOINT_B", "10.0.2.11:51820")

# Кого пингуем для измерения задержки (обычно IP без порта)
PING_A = ENDPOINT_A.split(":")[0]
PING_B = ENDPOINT_B.split(":")[0]

# Тюнинг
PING_COUNT = int(os.getenv("PING_COUNT", "3"))
PING_TIMEOUT = int(os.getenv("PING_TIMEOUT", "1"))
INTERVAL_SEC = float(os.getenv("INTERVAL_SEC", "3"))
LOSS_THRESHOLD = float(os.getenv("LOSS_THRESHOLD", "20"))      # %
SWITCH_DELTA_MS = float(os.getenv("SWITCH_DELTA_MS", "8"))     # гистерезис
STICKY_MIN_SEC = float(os.getenv("STICKY_MIN_SEC", "15"))      # hold-down
WINDOW = int(os.getenv("WINDOW", "5"))                         # окно сглаживания

rtt_re = re.compile(r"rtt min/avg/max/(?:mdev|stddev) = [\d\.]+/([\d\.]+)/")
loss_re = re.compile(r"(\d+(?:\.\d+)?)% packet loss")


def ping_stats(host: str):
    cmd = ["ping", "-c", str(PING_COUNT), "-W", str(PING_TIMEOUT), host]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")

    loss = 100.0
    avg = 9999.0

    m_loss = loss_re.search(out)
    if m_loss:
        loss = float(m_loss.group(1))

    m_rtt = rtt_re.search(out)
    if m_rtt:
        avg = float(m_rtt.group(1))

    return avg, loss


def set_endpoint(endpoint: str):
    subprocess.run(
        ["wg", "set", WG_INTERFACE, "peer", WG_PEER_PUBKEY, "endpoint", endpoint],
        check=False,
    )


def score(rtt, loss):
    # штраф за потери, чтобы "чистый" канал выигрывал при близком RTT
    return rtt + (loss * 5.0)


def main():
    hist_a = deque(maxlen=WINDOW)
    hist_b = deque(maxlen=WINDOW)

    current = None
    last_switch = 0.0

    while True:
        rtt_a, loss_a = ping_stats(PING_A)
        rtt_b, loss_b = ping_stats(PING_B)

        hist_a.append((rtt_a, loss_a))
        hist_b.append((rtt_b, loss_b))

        avg_rtt_a = sum(x[0] for x in hist_a) / len(hist_a)
        avg_loss_a = sum(x[1] for x in hist_a) / len(hist_a)
        avg_rtt_b = sum(x[0] for x in hist_b) / len(hist_b)
        avg_loss_b = sum(x[1] for x in hist_b) / len(hist_b)

        a_ok = avg_loss_a <= LOSS_THRESHOLD
        b_ok = avg_loss_b <= LOSS_THRESHOLD

        best = None
        if a_ok and b_ok:
            # основной критерий — задержка (с учетом небольшого штрафа за loss)
            s_a = score(avg_rtt_a, avg_loss_a)
            s_b = score(avg_rtt_b, avg_loss_b)
            best = "A" if s_a <= s_b else "B"
        elif a_ok:
            best = "A"
        elif b_ok:
            best = "B"

        now = time.time()

        print(
            f"A: rtt={avg_rtt_a:.1f}ms loss={avg_loss_a:.1f}% | "
            f"B: rtt={avg_rtt_b:.1f}ms loss={avg_loss_b:.1f}% | current={current}"
        )

        if best is None:
            print("No healthy channel")
        else:
            target_endpoint = ENDPOINT_A if best == "A" else ENDPOINT_B

            if current is None:
                set_endpoint(target_endpoint)
                current = best
                last_switch = now
                print(f"Initial channel -> {best} ({target_endpoint})")
            elif current != best:
                # антифлаппинг: переключаемся только если реально лучше и не слишком часто
                cur_rtt = avg_rtt_a if current == "A" else avg_rtt_b
                new_rtt = avg_rtt_a if best == "A" else avg_rtt_b
                improved = (cur_rtt - new_rtt) >= SWITCH_DELTA_MS
                sticky_ok = (now - last_switch) >= STICKY_MIN_SEC

                if improved and sticky_ok:
                    set_endpoint(target_endpoint)
                    current = best
                    last_switch = now
                    print(f"Switched -> {best} ({target_endpoint})")

        time.sleep(INTERVAL_SEC)


if __name__ == "__main__":
    main()
EOF
