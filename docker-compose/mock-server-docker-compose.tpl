version: "3.8"
services:
  mocked_server:
    image: public.ecr.aws/u4v1i0d4/test:latest
    ports:
      - "8080:8080"
    deploy:
      resources:
        limits:
          memory: 1G
