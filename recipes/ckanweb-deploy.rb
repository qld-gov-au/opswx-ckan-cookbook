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

include_recipe "datashades::ckanparams"

service_name = "ckan"

app = node['datashades']['ckan_web']['ckan_app']

config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"
virtualenv_dir = "/usr/lib/ckan/default"

# Setup Site directories
#
storage_root = "#{shared_fs_dir}/ckan_storage"
resource_cache = "#{shared_fs_dir}/resource_cache"
paths = {
	"#{storage_root}/storage" => service_name,
	"#{storage_root}/resources" => service_name,
	"#{storage_root}/webassets" => service_name,
	"#{resource_cache}" => service_name
}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
		owner dir_owner
		group "#{service_name}"
		recursive true
		mode '0775'
		action :create
	end

end

execute "Ensure files in storage have correct ownership" do
	command "find #{storage_root} #{resource_cache} -maxdepth 2 '!' -user #{service_name} -o '!' -group #{service_name} -execdir chown -R #{service_name}:#{service_name} '{}' ';'"
end

execute "Ensure files in storage have correct permissions" do
	command "find #{storage_root} #{resource_cache} -maxdepth 2 '!' -perm /g+rwX -execdir chmod -R g+rwX '{}' ';'"
end

#
# Install CKAN source
#

include_recipe "datashades::ckan-deploy"

#
# Clean up
#

# Just in case something created files as root
execute "Refresh virtualenv ownership" do
	command "chown -R ckan:ckan #{virtualenv_dir}"
end

#
# Create uWSGI config files
#

cookbook_file "#{config_dir}/ckan-uwsgi.ini" do
	source "ckan-uwsgi.ini"
	owner 'ec2-user'
	group 'ec2-user'
	mode "0744"
end

if system('yum info supervisor')
	cookbook_file "/etc/supervisord.d/supervisor-ckan-uwsgi.ini" do
		source "supervisor-ckan-uwsgi.conf"
		owner 'root'
		group 'root'
		mode "0744"
	end
else
	cookbook_file "/etc/systemd/system/ckan-uwsgi.service" do
		source "ckan-uwsgi.service"
		mode 0644
	end
end

#
# Create Apache config files
#

template "#{config_dir}/wsgi.py" do
	source 'apache.wsgi.erb'
	owner service_name
	group service_name
	mode '0755'
end

#
# Create NGINX Config files
#

# Handle old filename
nginx_config_file = "/etc/nginx/conf.d/#{node['datashades']['app_id']}.conf"
legacy_nginx_config = "/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf"
if (File.exist? legacy_nginx_config) then
	execute "mv #{legacy_nginx_config} #{nginx_config_file}"
end
template "#{nginx_config_file}" do
	source 'nginx.conf.erb'
	owner 'root'
	group 'root'
	mode '0755'
	variables({
		:app_name => app['shortname'],
		:app_url => node['datashades']['ckan_web']['site_domain']
		})
	not_if { node['datashades']['ckan_web']['endpoint'] != "/" }
	action :create
end

node.default['datashades']['auditd']['rules'].push("/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf")
