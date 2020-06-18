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

# Installing via yum gives initd integration, but has import problems.
# Installing via pip fixes the import problems, but doesn't provide the integration.
# So we do both.
execute "pip install supervisor"

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

# Explicitly set permissions on ckan directory so it's readable by Apache
#
directory '/home/ckan' do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
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

#
# Set up Python virtual environment
#

virtualenv_dir = "/usr/lib/ckan/default"

execute "Install Python Virtual Environment" do
	user "root"
	command "pip install virtualenv"
end

bash "Create CKAN Default Virtual Environment" do
	user "root"
	code <<-EOS
		/usr/bin/virtualenv --no-site-packages #{virtualenv_dir}
		chown -R ckan:ckan #{virtualenv_dir}
	EOS
	not_if { ::File.directory? "#{virtualenv_dir}/bin" }
end

bash "Fix VirtualEnv lib issue" do
	user "ckan"
	group "ckan"
	cwd "#{virtualenv_dir}"
	code <<-EOS
		mv -f lib/python2.7/site-packages lib64/python2.7/
		rm -rf lib
		ln -sf lib64 lib
	EOS
	not_if { ::File.symlink? "#{virtualenv_dir}/lib" }
end

#
# Create CKAN configuration directory
#

directory "#{virtualenv_dir}/etc" do
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

link "/etc/ckan/default" do
	to "#{virtualenv_dir}/etc"
	link_type :symbolic
end
