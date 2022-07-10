#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: datapusher-setup
#
# Installs DataPusher requirements
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


include_recipe "datashades::default"

service_name = "datapusher"
virtualenv_dir = "/usr/lib/ckan/#{service_name}"

# Create group and user so they're allocated a UID and GID clear of OpsWorks managed users
#
group "#{service_name}" do
	action :create
	gid 1005
end

user "#{service_name}" do
	comment "DataPusher User"
	home "/home/#{service_name}"
	action :create
	uid 1005
	gid 1005
end

# Install necessary packages
#
node['datashades'][service_name]['packages'].each do |p|
	package p
end

# Create and mount EFS Data directory
# Needs to come after package installation so the 'apache' user exists
#
include_recipe "datashades::httpd-efs-setup"

#
# Set up Python virtual environment
#

execute "Install Python Virtual Environment" do
	user "root"
	command "pip --cache-dir=/tmp/ install virtualenv"
end

bash "Create Virtual Environment" do
	user "root"
	code <<-EOS
		PATH="$PATH:/usr/local/bin"
		virtualenv "#{virtualenv_dir}"
		chown -R #{service_name}:#{service_name} "#{virtualenv_dir}"
	EOS
	not_if { ::File.directory? "#{virtualenv_dir}/bin" }
end

datashades_move_and_link "#{virtualenv_dir}/lib" do
	target "#{virtualenv_dir}/lib64"
	owner 'ckan'
end

#
# Create CKAN configuration directory
#

directory "/etc/ckan" do
  owner "#{service_name}"
  group "#{service_name}"
  mode '0755'
  action :create
  recursive true
  # If we happen to be sharing the box with another CKAN virtualenv, don't steal ownership
  not_if { ::File.exist? "/etc/ckan" }
end

#
# Add DataPusher to DNS
#

bash "Add #{service_name} DNS entry" do
	user "root"
	code <<-EOS
		sed -i "/#{service_name}_/d" /etc/hostnames
		echo "#{service_name}_name=#{node['datashades']['app_id']}#{service_name}.#{node['datashades']['tld']}" >> /etc/hostnames
	EOS
end

cookbook_file '/bin/updatedns' do
	source 'updatedns'
	owner 'root'
	group 'root'
	mode '0755'
end

execute "Update #{node['datashades']['hostname']} #{service_name} DNS" do
	command	'/bin/updatedns'
	user 'root'
	group 'root'
end
