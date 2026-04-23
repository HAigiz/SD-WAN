#!/usr/bin/env python3
import os, re, time, subprocess
from collections import deque

# КЛЮЧИ ТЕПЕРЬ ТУТ ЖЕСТКО
WG_INTERFACE = "wg0"
WG_PEER_PUBKEY = "qytmeodjJiNA8kpwyb9edn/d4lnOwmoENcyff8kleCk="
ENDPOINT_A = "10.0.1.12:51820"
ENDPOINT_B = "10.0.2.12:51820"

PING_A, PING_B = ENDPOINT_A.split(":")[0], ENDPOINT_B.split(":")[0]
INTERVAL_SEC = 5
LOSS_THRESHOLD = 20
WINDOW = 3

rtt_re = re.compile(r"rtt min/avg/max/.* = [\d\.]+/([\d\.]+)/")
loss_re = re.compile(r"(\d+(?:\.\d+)?)% packet loss")

def ping_stats(host):
    try:
        proc = subprocess.run(["ping", "-c", "3", "-W", "1", host], capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        loss = 100.0
        avg = 9999.0
        m_loss = loss_re.search(out)
        if m_loss: loss = float(m_loss.group(1))
        m_rtt = rtt_re.search(out)
        if m_rtt: avg = float(m_rtt.group(1))
        return avg, loss
    except: return 9999.0, 100.0

def set_endpoint(endpoint):
    print(f"--- SWITCHING ENDPOINT TO: {endpoint} ---")
    subprocess.run(["wg", "set", WG_INTERFACE, "peer", WG_PEER_PUBKEY, "endpoint", endpoint])

def main():
    hist_a, hist_b = deque(maxlen=WINDOW), deque(maxlen=WINDOW)
    current = None
    print(f"Monitor started for peer: {WG_PEER_PUBKEY[:10]}...")
    while True:
        r_a, l_a = ping_stats(PING_A)
        r_b, l_b = ping_stats(PING_B)
        hist_a.append((r_a, l_a))
        hist_b.append((r_b, l_b))
        
        avg_l_a = sum(x[1] for x in hist_a) / len(hist_a)
        avg_l_b = sum(x[1] for x in hist_b) / len(hist_b)
        avg_r_a = sum(x[0] for x in hist_a) / len(hist_a)
        avg_r_b = sum(x[0] for x in hist_b) / len(hist_b)

        # Логика: приоритет Каналу B (быстрый), если он живой
        best = "B" if avg_l_b < LOSS_THRESHOLD else ("A" if avg_l_a < LOSS_THRESHOLD else None)
        
        if best and best != current:
            set_endpoint(ENDPOINT_A if best == "A" else ENDPOINT_B)
            current = best
        
        print(f"Stats | A: {avg_r_a:.1f}ms/{avg_l_a}% | B: {avg_r_b:.1f}ms/{avg_l_b}% | Active: {current}")
        time.sleep(INTERVAL_SEC)

if __name__ == '__main__':
    main()
