#!/bin/bash
# File: reload-prometheus.sh
# Purpose: Reload Prometheus configuration

curl -X POST http://127.0.0.1:9090/-/reload