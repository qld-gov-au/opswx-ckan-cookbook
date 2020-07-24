#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: httpd-configure
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2019, Queensland Government
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

include_recipe "datashades::default-configure"

execute "Extend Apache log rotation" do
	user "root"
	cwd "/etc/logrotate.d"
	# this replacement needs to be idempotent; the result must not match the original pattern
	# use single quotes so we don't have to double our backslashes
	command 'sed -i "s|\(/var/log/httpd/\*log\) {|\1\n/var/log/httpd/*/*log {|" httpd'
end

file "/etc/cron.daily/archive-apache-logs-to-s3" do
	content "/usr/local/bin/archive-logs.sh httpd >/dev/null 2>&1\n"
	owner "root"
	group "root"
	mode "0755"
end

# Re-enable and start in case it was stopped by previous recipe versions and reload if already started
service 'httpd' do
	supports :restart => true, :reload => true, :status => true
	action [:enable, :start, :reload]
end

cookbook_file '/etc/cron.hourly/httpd-reload-on-low-memory' do
	source "httpd-reload-on-low-memory"
	mode "0755"
	owner "root"
	group "root"
end
