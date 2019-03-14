#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: deploy-ckanweb
#
# Deploys OpsWorks CKAN App to web layer
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

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:ckan-#{node['datashades']['version']}*").first
end
config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"

# Define CKAN endpoint NGINX location directive
#
node.override['datashades']['app']['locations'] = "location ~ ^#{node['datashades']['ckan_web']['endpoint']} { proxy_pass http://localhost:8000; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; }"

node.default['datashades']['auditd']['rules'].push("#{config_file}")
node.default['datashades']['auditd']['rules'].push("/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf")


# Create NGINX Config file
#
template "/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf" do
  source 'nginx.conf.erb'
  owner 'root'
  group 'root'
  mode '0755'
  variables({
   		:app_name =>  app['shortname'],
		:app_url => app['domains'][0]

		})
	not_if { node['datashades']['ckan_web']['endpoint'] != "/" }
	action :create
end

# Setup Site directories
#
paths = {"#{shared_fs_dir}" => 'ckan', "#{shared_fs_dir}/ckan_storage/storage" => 'apache', "#{shared_fs_dir}/ckan_storage/resources" => 'apache', "/var/log/nginx/#{app['shortname']}" => 'nginx', "/var/log/apache/#{app['shortname']}" => 'apache'}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
	  owner dir_owner
	  recursive true
	  mode '0775'
	  action :create
	end
end

directory "#{shared_fs_dir}/private" do
	owner "root"
	mode '0700'
	action :create
end

apprelease = app['app_source']['url']
apprelease.sub! 'ckan/archive/', "ckan.git@"
apprelease.sub! '.zip', ""
version = apprelease[/@(.*)/].sub! '@', ''

virtualenv_dir = "/usr/lib/ckan/default"
activate = ". #{virtualenv_dir}/bin/activate"
pip = "#{virtualenv_dir}/bin/pip"
paster = "#{virtualenv_dir}/bin/paster --plugin=ckan"
install_dir = "#{virtualenv_dir}/src/ckan"
execute "Install CKAN #{version}" do
	user "ckan"
	group "ckan"
	command "#{pip} install -e 'git+#{apprelease}#egg=ckan'"
	not_if { ::File.exist? "#{install_dir}/requirements.txt" }
end

bash "Install Python dependencies" do
	user "ckan"
	group "ckan"
	code <<-EOS
		#{activate}
		pip install --cache-dir=/tmp/ -r '#{install_dir}/requirements.txt'
		pip install --cache-dir=/tmp/ --upgrade setuptools bleach
	EOS
end

template "#{config_file}" do
	source 'ckan_properties.ini.erb'
	owner 'ckan'
	group 'ckan'
	mode '0755'
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0]
	})
	action :create
end

execute "Init CKAN DB" do
	user "root"
	command "#{paster} db init -c #{config_file} 2>&1 >> '#{shared_fs_dir}/private/ckan_db_init.log.tmp' && mv '#{shared_fs_dir}/private/ckan_db_init.log.tmp' '#{shared_fs_dir}/private/ckan_db_init.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_db_init.log" }
end

cookbook_file "#{virtualenv_dir}/bin/activate_this.py" do
	source 'activate_this.py'
	owner 'ckan'
	group 'ckan'
	mode '0755'
end

link "#{config_dir}/who.ini" do
	to "#{install_dir}/who.ini"
	link_type :symbolic
end

template "#{config_dir}/apache.wsgi" do
	source 'apache.wsgi.erb'
	owner 'root'
	group 'root'
	mode '0755'
end

template '/etc/httpd/conf.d/ckan.conf' do
	source 'apache_ckan.conf.erb'
	owner 'apache'
	group 'apache'
	mode '0755'
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0]
	})
	action :create
end

# Install Raven for Sentry
#
execute "Install Raven Sentry client" do
	user "ckan"
	command "#{pip} install --cache-dir=/tmp/ --upgrade raven"
end

# Install CKAN extensions
#
include_recipe "datashades::ckanweb-deploy-exts"

# Just in case something created files as root
execute "Refresh virtualenv ownership" do
	user "root"
	group "root"
	command "chown -R ckan:ckan #{virtualenv_dir}"
end

# Prepare front-end CSS and JavaScript
# This needs to be after any extensions since they may affect the result.
execute "Create front-end resources" do
	user "ckan"
	group "ckan"
	command "#{paster} front-end-build -c #{config_file}"
end

# Update tracking data
#
execute "Tracking update" do
	user "root"
	command "#{paster} tracking update -c #{config_file} 2>&1 >> '#{shared_fs_dir}/private/tracking-update.log.tmp' && mv '#{shared_fs_dir}/private/tracking-update.log.tmp' '#{shared_fs_dir}/private/tracking-update.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/tracking-update.log" }
end

# Build the Solr search index in case we have pre-existing data.
execute "Build search index" do
	user "root"
	command "#{paster} search-index rebuild -r -o -c #{config_file} 2>&1 > '#{shared_fs_dir}/private/solr-index-build.log'"
end

# Restart Web services to enable new configurations
#
services = [ 'php-fpm-5.5', 'nginx', 'httpd' ]

services.each do |servicename|
	service servicename do
		action [:restart]
	end
end

# Create admin user
#
bash "Create CKAN Admin user" do
	user "root"
	code <<-EOS
		#{activate}
		paster --plugin=ckan user add sysadmin password="#{node['datashades']['ckan_web']['adminpw']}" email="#{node['datashades']['ckan_web']['adminemail']}" -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp"
		paster --plugin=ckan sysadmin add sysadmin -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp" && mv "#{shared_fs_dir}/private/ckan_admin.log.tmp" "#{shared_fs_dir}/private/ckan_admin.log"
	EOS
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_admin.log"}
end
