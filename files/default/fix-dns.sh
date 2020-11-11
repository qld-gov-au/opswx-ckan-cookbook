#!/bin/sh

dns_ok () {
  # Check if DNS is working
  /usr/bin/dig example.com +time=1 +tries=1 >/dev/null 2>&1 || return 1
}

dns_ok && exit 0

# Check if the /tmp directory is available
ls /tmp/ >/dev/null 2>&1 || (echo "/tmp is not available, running OpsWorks setup"; /opt/aws/opsworks/current/bin/opsworks-agent-cli run_command setup)

# Check if DNS is fully active
dns_ok || (echo "DNS is not available, restarting network service"; service network restart)
