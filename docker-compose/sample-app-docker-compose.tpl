version: "3.8"
services:
  ot-metric-emitter:
    privileged: true
    image: quay.io/freshtracks.io/avalanche:latest
    command: --port=${port} --metric-count=${metric-count} --label-count=${label-count} --series-count=${series-count}
    ports:
      - ${port}:${port}
    deploy:
      resources:
        limits:
          memory: 16G