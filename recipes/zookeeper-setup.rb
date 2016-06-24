#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: zookeeper-setup
#
# Installs Zookeeper to Solr Layer
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

service_name = 'zk'

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
		hostcount=$(($(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --query "ResourceRecordSets[?contains(Name, '#{node['datashades']['version']}#{service_name}')].Name" | jq '. | length') + 1))
		echo "#{service_name}_name=#{node['datashades']['version']}#{service_name}${hostcount}.#{node['datashades']['tld']}" >> /etc/hostnames
		echo ${hostcount} > /etc/zkid
	EOS
	not_if "grep -q '#{service_name}_name' /etc/hostnames"
end

# Create script to update DNS on configure events
#
cookbook_file '/sbin/updatedns' do
	source 'updatedns'
	owner 'root'
	group 'root'
	mode '0755'
end


