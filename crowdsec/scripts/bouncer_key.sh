#!/bin/bash
# File: bouncer_key.sh
# Purpose: Add Traefik bouncer to CrowdSec

docker exec crowdsec cscli bouncers add traefik-bouncer
sleep 1
docker exec crowdsec cscli bouncers add firewall-bouncer