#!/bin/bash
# File: add_user.sh
# Purpose: Add user/passwd to CrowdSec

docker exec crowdsec cscli machines add crowdsec-web-ui --password testing -f /dev/null