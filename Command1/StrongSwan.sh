#!/bin/bash

SHARED_SECRET="SuperSecretIPsecKey123"

mkdir -p filial1/ipsec filial2/ipsec

# --- КОНФИГУРАЦИЯ FILIAL 1 ---
cat > filial1/ipsec/swanctl.conf << EOF
connections {
    rw {
        local_addrs  = 10.0.1.11
        remote_addrs = 10.0.1.12
        local {
            auth = psk
            id = filial1
        }
        remote {
            auth = psk
            id = filial2
        }
        children {
            net-net {
                local_ts  = 192.168.100.1/32
                remote_ts = 192.168.100.2/32
                start_action = trap
            }
        }
    }
}
secrets {
    ike-psk {
        id = filial2
        secret = $SHARED_SECRET
    }
}
EOF

# --- КОНФИГУРАЦИЯ FILIAL 2 ---
cat > filial2/ipsec/swanctl.conf << EOF
connections {
    rw {
        local_addrs  = 10.0.1.12
        remote_addrs = 10.0.1.11
        local {
            auth = psk
            id = filial2
        }
        remote {
            auth = psk
            id = filial1
        }
        children {
            net-net {
                local_ts  = 192.168.100.2/32
                remote_ts = 192.168.100.1/32
                start_action = trap
            }
        }
    }
}
secrets {
    ike-psk {
        id = filial1
        secret = $SHARED_SECRET
    }
}
EOF
