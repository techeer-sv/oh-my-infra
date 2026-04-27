# Loki Driver를 Docker에서 사용하기

## Install
```
docker plugin install grafana/loki-docker-driver:3.7.0-amd64 --alias loki --grant-all-permissions
```

## Run
```
make server
```

## Result
below should output `loki`
```
docker inspect -f '{{.HostConfig.LogConfig.Type}}' django-app-loki
```