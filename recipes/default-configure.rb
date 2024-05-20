#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default-configure
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2016, Link Digital
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "datashades::stackparams"

# Add a larger swapfile if we have spare disk space
#
include_recipe "datashades::swapfile"

template "/usr/local/bin/archive-logs.sh" do
    source "archive-logs.sh.erb"
    owner "root"
    group "root"
    mode "0755"
end

# Archive regular system logs to S3.
# This will automatically compress anything at /var/log, but not recursively;
# however, if logs in subdirectories are already compressed by logrotate,
# then they will be archived too.
file "/etc/cron.daily/archive-system-logs-to-s3" do
    content "LOG_DIR=/var/log /usr/local/bin/archive-logs.sh system >/dev/null 2>&1\n"
    owner "root"
    group "root"
    mode "0755"
end

# Archive logs on system shutdown
cookbook_file "/etc/systemd/system/logrotate-shutdown.service" do
    source "logrotate-shutdown.service"
    owner "root"
    group "root"
    mode "0744"
end

service "logrotate-shutdown" do
    action [:enable,:start]
end

# Run custom actions on system shutdown
file "/etc/rc0.d/S01heartbeat" do
    content "rm /data/*-healthcheck_#{node['datashades']['hostname']}; archive-logs system"
end

# Run updateDNS script
#
execute 'update dns' do
    command '/bin/updatedns'
    user 'root'
    group 'root'
    only_if { ::File.exist? "/bin/updatedns" }
end

# Recover from DNS failures
#
cookbook_file "/usr/local/bin/fix-dns.sh" do
    source "fix-dns.sh"
    owner "root"
    group "root"
    mode "0744"
end

file "/etc/cron.d/fix-dns" do
    content "*/5 * * * * root /usr/local/bin/fix-dns.sh\n"
    mode '0644'
end

# Update custom auditd rules
#
template '/etc/audit/rules.d/link.rules' do
    source 'auditd.rules.erb'
    owner 'root'
end

# Remove unwanted cron job from previous script versions
#
file '/etc/cron.daily/manageadmins' do
    action :delete
end

file "/etc/cron.daily/clamav-tmp-file-cleanup" do
	content "rm -r /var/lib/clamav/tmp.* >/dev/null 2>&1\n"
	owner "root"
	group "root"
	mode "0755"
end

service 'aws-smtp-relay' do
    action [:enable, :restart]
end

service "supervisord start" do
    service_name "supervisord"
    supports restart: true
    action [:restart]
end

# Re-enable and start in case it was stopped by previous recipe versions
if system('which postfix') then
    mailer_daemon = 'postfix'
else
    mailer_daemon = 'sendmail'
end
service mailer_daemon do
    action [:enable, :start]
end
