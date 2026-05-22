FROM debian:bookworm-slim

RUN apt-get update -qq && apt-get install -y \
    openssh-client \
    sshpass \
    nmap \
    proxychains4 \
    default-mysql-client \
    curl \
    python3 \
    iputils-ping \
    net-tools \
    nano \
    && rm -rf /var/lib/apt/lists/*

# ProxyChains preconfigurado para SOCKS5 en 1080
RUN sed -i \
    -e 's/^socks4.*//' \
    -e '/^\[ProxyList\]/a socks5 127.0.0.1 1080' \
    /etc/proxychains4.conf

# SSH sin verificación de host (aceptable en lab)
RUN mkdir -p /root/.ssh && \
    printf 'Host 172.28.0.10\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n' \
    > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

CMD ["tail", "-f", "/dev/null"]
