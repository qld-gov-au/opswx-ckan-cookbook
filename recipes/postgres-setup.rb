#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: postgres-setup
#
# Installs postgres role to Layer
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


include_recipe "datashades::default"

# Service name used by DNS functionality only in this recipe
#
service_name = 'pg'

# Install necessary packages
#
node['datashades'][service_name]['packages'].each do |p|
	package p
end

# Add DNS entry for service host
#
bash "Add #{service_name} DNS entry" do
	user "root"
	code <<-EOS
		zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
		reccount=$(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --query "ResourceRecordSets[?contains(Name, '#{node['datashades']['version']}#{service_name}')].Name" | jq '. | length')
		aliascount=$(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --query "ResourceRecordSets[?contains(Name, '#{node['datashades']['version']}#{service_name}.')].Name" | jq '. | length')
		hostcount=`expr $reccount - $aliascount + 1`
		echo ${hostcount} > /etc/#{service_name}id
		if [ ${hostcount} -eq 1 ]; then
			echo "#{service_name}_master=#{node['datashades']['version']}#{service_name}${hostcount}.#{node['datashades']['tld']}" >> /etc/hostnames
		else
			echo "#{service_name}_slave=#{node['datashades']['version']}#{service_name}${hostcount}.#{node['datashades']['tld']}" >> /etc/hostnames	
		fi
	EOS
	not_if "grep -q '#{service_name}_' /etc/hostnames"
end

# Create script to update DNS on configure events
#
cookbook_file '/sbin/updatedns' do
	source 'updatedns'
	owner 'root'
	group 'root'
	mode '0755'
end

# Run updateDNS script
#
execute "Update #{node['datashades']['hostname']} #{service_name} DNS" do
	command	'/sbin/updatedns'
	user 'root'
	group 'root'
end

pgserv = "postgresql" + node['datashades']['postgres']['version']

# Enable service start at boot
service "#{pgserv}" do
	action [:enable, :start]	
end
