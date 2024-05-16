#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-configure
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

include_recipe "datashades::default-configure"

service_name = 'solr'

# Add instance to pool

file "/data/solr-healthcheck_#{node['datashades']['hostname']}" do
	action :touch
end

cron "Solr health check" do
	action :delete
end

file "/etc/cron.d/solr-healthcheck" do
	content "* * * * * root /usr/local/bin/solr-healthcheck.sh > /dev/null 2>&1\n"
	mode "0644"
end

# synchronise Solr cores via EFS
file "/etc/cron.d/solr-sync" do
	content "*/5 * * * * root /usr/local/bin/solr-sync.sh >> /var/log/solr/solr-sync.cron.log 2>&1\n"
	mode "0644"
end

# Add DNS entry for service host
#
bash "Add #{service_name} DNS entry" do
	user "root"
	code <<-EOS
		server_id=$(echo "#{node['datashades']['hostname']}" |tr -cd '[[:digit:]]')
		echo "${server_id}" > /etc/#{service_name}id
		sed -i "/#{service_name}_/d" /etc/hostnames
		if [ "${server_id}" -eq 1 ]; then
			failover_type=master
		else
			failover_type=slave
		fi
		alias="#{node['datashades']['app_id']}#{service_name}${server_id}.#{node['datashades']['tld']}"
		echo "#{service_name}_${failover_type}=${alias}" >> /etc/hostnames
	EOS
end
