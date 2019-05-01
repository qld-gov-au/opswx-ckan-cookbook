#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: datapusher-shutdown
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2019, Queensland Government
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

include_recipe "datashades::httpd-shutdown"

# Hide this instance from others
#
file "/data/#{node['datashades']['hostname']}" do
	action :delete
end

bash "Archive remaining logs" do
	user "root"
	cwd "/"
	code <<-EOS
		/etc/cron.daily/logrotate
		TIMESTAMP=`date +'%s'`
		for logfile in `ls -d /var/log/nginx/*log /var/log/nginx/*/*log`; do
			mv "$logfile" "$logfile.$TIMESTAMP"
			gzip "$logfile.$TIMESTAMP"
		done
		/usr/local/sbin/archive-logs.sh nginx
	EOS
end