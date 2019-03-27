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

# Enable rotation of Apache logs in subdirectories
#
execute "Extend Apache log rotation" do
	user "root"
	cwd "/etc/logrotate.d"
	# this replacement needs to be idempotent; the result must not match the original pattern
	# use single quotes so we don't have to double our backslashes
	command 'sed -i "s|\(/var/log/httpd/\*log\) {|\1\n/var/log/httpd/*/*log {|;s|delaycompress|compress|g" httpd'
end

template "/usr/local/sbin/archive-logs.sh" do
	source "archive-logs.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.daily/archive-apache-logs-to-s3" do
	content "/usr/local/sbin/archive-logs.sh httpd 2>&1 >/dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end

service 'httpd' do
	action [:restart]
end
