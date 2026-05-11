#!/bin/bash
# File: secured.sh
# Purpose: Create Docker networks for crowdsec

docker network create secured-traefik-network
sleep 1
docker network create crowdsec-network
sleep 1
echo "All networks created successfully."