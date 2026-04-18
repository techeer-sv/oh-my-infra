#!/bin/bash
# File: create-networks.sh
# Purpose: Create Docker networks for logging, metrics, tracing, and visualization

docker network create logging-network
sleep 1
docker network create metrics-network
sleep 1
docker network create tracing-network
sleep 1
docker network create profiling-network
sleep 1
docker network create traefik-network
sleep 1
docker network create grafana-network
sleep 1
echo "All networks created successfully."