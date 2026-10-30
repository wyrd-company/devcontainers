FROM alpine:3

RUN apk add --no-cache git openssh-server \
    && adduser -D -s /bin/sh git \
    && echo "git:$(head -c 24 /dev/urandom | base64)" | chpasswd \
    && install -d -o git -g git -m 0700 /home/git/.ssh \
    && install -d -o git -g git /srv/git \
    && ssh-keygen -A \
    && printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >>/etc/ssh/sshd_config

CMD ["/usr/sbin/sshd", "-D", "-e"]
