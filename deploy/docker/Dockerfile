FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ethtool \
    iproute2 \
    procps \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/ /opt/ai-host-observability/scripts/

ENV OUT_DIR=/textfile_collector

ENTRYPOINT ["/bin/bash", "-c", "while true; do OUT_DIR=$OUT_DIR bash /opt/ai-host-observability/scripts/collect-all.sh; sleep 60; done"]
