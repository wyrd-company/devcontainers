ARG IMAGE=devcontainers-base:noble
FROM ${IMAGE}

COPY service /etc/s6-overlay/s6-rc.d/restart-probe
RUN chmod 0755 /etc/s6-overlay/s6-rc.d/restart-probe/run \
    && mkdir -p /etc/s6-overlay/s6-rc.d/restart-probe/dependencies.d \
    && touch /etc/s6-overlay/s6-rc.d/restart-probe/dependencies.d/base \
    && touch /etc/s6-overlay/user-bundles.d/user/contents.d/restart-probe

COPY setup-probe /etc/s6-overlay/s6-rc.d/setup-probe
COPY ready-probe /etc/s6-overlay/s6-rc.d/ready-probe
COPY --chmod=0755 legacy-run /etc/services.d/legacy-enabled/run
COPY --chmod=0755 legacy-run /etc/services.d/legacy-manual/run
RUN chmod 0755 /etc/s6-overlay/s6-rc.d/setup-probe/start /etc/s6-overlay/s6-rc.d/ready-probe/run \
    && touch /etc/services.d/legacy-manual/down \
    && mkdir -p /etc/s6-overlay/user-bundles.d/user2/contents.d \
    && touch /etc/s6-overlay/user-bundles.d/user2/contents.d/setup-probe \
             /etc/s6-overlay/user-bundles.d/user2/contents.d/ready-probe
