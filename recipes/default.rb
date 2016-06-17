#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default
#
# Implements base configuration for instances
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

# Set timezone to default value
#
link "/etc/localtime" do
  to "/usr/share/zoneinfo/#{node['datashades']['timezone']}"
  link_type :symbolic
end

# Store timezone config so yum updates don't reset the timezone
#
template '/etc/sysconfig/clock' do
  source 'clock.erb'
  owner 'root'
  group 'root'
  mode '0755'
end

# Install core packages
#
node['datashades']['core']['packages'].each do |p|
  package p
end

# Enable yum-cron so updates are downloaded on running nodes
#
service "yum-cron" do
	action [:enable, :start]
end

# Enable nano syntax highlighing
#
cookbook_file '/etc/nanorc' do
  source 'nanorc'
  owner 'root'
  group 'root'
  mode '0755'
end

# Add some helpful stuff to bash
#
cookbook_file "/etc/profile.d/datashades.sh" do
	source "datashades_bash.sh"
	owner 'root'
	group 'root'
	mode '0755'
end

# Make sure all instances have an /etc/zoneid
#
bash "Adding AWS ZoneID" do
	user "root"
	code <<-EOS
	if [ ! -e /etc/awszoneid ]; then 
		zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
		echo "zoneid=${zoneid}" > /etc/awszoneid
	fi
	EOS
end
