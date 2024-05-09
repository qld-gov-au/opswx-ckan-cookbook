#!/bin/sh

dns_ok () {
  # Check if DNS is working
  dig example.com +time=1 +tries=1 >/dev/null 2>&1 || return 1
}

# Check if DNS is fully active
dns_ok || (echo "DNS is not available, restarting network service"; service network restart)
