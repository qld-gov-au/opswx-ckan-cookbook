#
# Author:: Carl Antuar (<carl.antuar@qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: httpd-efs-setup
#
# Updates DNS and mounts whenever instance leaves or enters the online state or EIP/ELB config changes
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

# Update EFS Data directory for Apache logging
#
include_recipe "datashades::efs-setup"

data_paths =
{
	"/data/logs/apache/#{node['datashades']['instid']}" => 'apache'
}

data_paths.each do |data_path, dir_owner|
	directory data_path do
	  owner dir_owner
	  group 'ec2-user'
	  mode '0775'
	  recursive true
	  action :create
	end
end

link_paths =
{
	"/var/log/httpd/#{node['datashades']['sitename']}" => "/data/logs/apache/#{node['datashades']['instid']}"
}

link_paths.each do |link_path, source_path|
	link link_path do
		to source_path
		link_type :symbolic
	end
end
