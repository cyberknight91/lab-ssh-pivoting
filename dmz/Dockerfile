FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y openssh-server iputils-ping net-tools && \
    rm -rf /var/lib/apt/lists/*

# Usuario de lab para las demos
RUN useradd -m -s /bin/bash pivot && \
    echo 'pivot:pivot123' | chpasswd

# Habilitar autenticación por contraseña y forwarding
RUN sed -i \
    -e 's/#PasswordAuthentication yes/PasswordAuthentication yes/' \
    -e 's/PasswordAuthentication no/PasswordAuthentication yes/' \
    /etc/ssh/sshd_config && \
    printf '\nPasswordAuthentication yes\nAllowTcpForwarding yes\nGatewayPorts yes\n' \
    >> /etc/ssh/sshd_config

# Generar claves de host y directorio de runtime
RUN ssh-keygen -A && mkdir -p /run/sshd

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
