version: "3.8"
services:
  prometheus:
    image: prom/prometheus:latest
    command: --config.file=/etc/prometheus/prometheus.yml --enable-feature=agent
    environment:
      - AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN
    volumes:
      - .:/etc/prometheus
      - ~/.aws:/root/.aws
    ports:
      - '9090:9090'
