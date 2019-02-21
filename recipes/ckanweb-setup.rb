#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-setup
#
# Creates NGINX Web server for CKAN
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

# Create ASG helper script
#
cookbook_file "/sbin/updateasg" do
	source "updateasg"
	owner 'root'
	group 'root'
	mode '0755'
end

# Install CKAN services and dependencies
#
node['datashades']['ckan_web']['packages'].each do |p|
	package p
end

include_recipe "datashades::nginx-setup"
include_recipe "datashades::ckanweb-efs-setup"


# Change Apache default port to 8000 and fix access to /
#
bash "Change Apache config" do
	user 'root'
	group 'root'
	code <<-EOS
	sed -i 's~Listen 80~Listen 8000~g' /etc/httpd/conf/httpd.conf
	sed -i '/<Directory /{n;n;s/Require all denied/# Require all denied/}' /etc/httpd/conf/httpd.conf
	EOS
	not_if "grep 'Listen 8000' /etc/httpd/conf/httpd.conf"
end

# Enable Apache service
#
service 'httpd' do
	action [:enable]
end

# Get app details so we can version the app setup
#
app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
apprelease = app['app_source']['url']
apprelease.sub! 'ckan/archive/', "ckan.git@" 			
apprelease.sub! '.zip', ""
version = apprelease[/@(.*)/].sub! '@', ''

# Create CKAN Group
#
group "ckan" do
	action :create
	gid '1000'	
end

# Create CKAN User
#
user "ckan" do
	comment "CKAN User"
	home "/home/ckan"
	shell "/sbin/nologin"
	action :create
	uid '1000'
	group 'ckan'	
end

# Explicity set permissions on ckan directory so it's readable by Apache
#
directory '/home/ckan' do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
end


# Create ckan app location
#
directory "/usr/lib/ckan/default" do
  owner 'ckan'
  group 'ckan'
  mode '0755'
  action :create
  recursive true
end

# Install Virtual Environment
#
execute "Install Python Virtual Environment" do
	user "root"
	command "pip install virtualenv"
	not_if "pip list | grep virtualenv"
end

# Create VirtualEnv for CKAN
#
if !::File.directory?("/usr/lib/ckan/default/bin")
	execute "Create CKAN Default Virtual Environment" do
		cwd "/usr/lib/ckan"
		user "root"
		command "/usr/bin/virtualenv --no-site-packages /usr/lib/ckan/default"
	end
	
	bash "Fix VirtualEnv lib issue" do
		user "root"
		cwd "/usr/lib/ckan/default"
		code <<-EOS
		mv -f lib/python2.7/site-packages lib64/python2.7/
		rm -rf lib
		ln -sf lib64 lib 
		EOS
	end
	
	
end

# Create CKAN default etc directory
#
directory "/usr/lib/ckan/default/etc" do
  owner 'ckan'
  group 'ckan'
  mode '0755'
  action :create
  recursive true
end

directory "/etc/ckan" do
  owner 'ckan'
  group 'ckan'
  mode '0755'
  action :create
  recursive true
end

# Link /etc/ckan to actual CKAN location
#
link "/etc/ckan/default" do
	to "/usr/lib/ckan/default/etc"
	link_type :symbolic
end


