#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-setup
#
# Installs Solr role to Layer
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

service_name = 'solr'

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
		echo "#{service_name}_name=#{node['datashades']['version']}#{service_name}.#{node['datashades']['tld']}" >> /etc/hostnames
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


