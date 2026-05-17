source: file
filenames:
  - /var/log/traefik/access.log
labels:
  type: traefik

appsec_config: crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 0.0.0.0:7422
source: appsec
name: myAppSecComponent

source: journalctl
journalctl_filter:
  - "_SYSTEMD_UNIT=ssh.service"
labels:
  type: syslog