#
# Cookbook Name:: datashades
# Recipe:: ckan-deploy
#
# Deploys OpsWorks CKAN App
#
# Copyright 2021, Queensland Government
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

require 'date'

include_recipe "datashades::ckanparams"

service_name = "ckan"

app = node['datashades']['ckan_web']['ckan_app']

config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"
virtualenv_dir = "/usr/lib/ckan/default"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

log "#{DateTime.now}: Creating files and directories for CKAN"

cookbook_file "#{virtualenv_dir}/bin/ckan_cli" do
	source 'ckan_cli'
	owner "#{service_name}"
	group "#{service_name}"
	mode "0755"
end

# Setup Site directories
#
paths = {
	"/var/log/#{service_name}" => service_name,
	shared_fs_dir => service_name,
	"/var/cache/#{service_name}" => service_name,
}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
		owner dir_owner
		group service_name
		recursive true
		mode '0755'
		action :create
	end
end

directory "#{shared_fs_dir}/private" do
	owner "root"
	mode '0700'
	action :create
end

#
# Install selected revision of CKAN core
#

log "#{DateTime.now}: Installing pinned dependencies for CKAN"

# #pyOpenSSL 22.0.0 (2022-01-29) - dropped py2 support but has issues on py3 which stops harvester working
# #pyOpenSSL 23.0.0 (2023-01-01) - required due to harvest:  Error: HTTP general exception: module 'lib' has no attribute 'SSL_CTX_set_ecdh_auto'
execute "Pin dependency versions" do
	user service_name
	group service_name
	command "#{pip} install 'setuptools>=44.1.0,<71' 'pyOpenSSL>=23.0.0'"
end

log "#{DateTime.now}: Installing CKAN source"
datashades_pip_install_app "ckan" do
	type app['app_source']['type']
	revision app['app_source']['revision']
	url app['app_source']['url']
end

# Just in case something created files as root
execute "Refresh virtualenv ownership" do
	command "chown -RH ckan:ckan #{virtualenv_dir}"
end

#
# Set up CKAN configuration files
#

template config_file do
	source 'ckan_properties.ini.erb'
	owner service_name
	group service_name
	mode "0755"
	variables({
		:app_name =>  app['shortname'],
		:app_url => node['datashades']['ckan_web']['site_domain'],
		:src_dir => "#{virtualenv_dir}/src",
		:email_domain => node['datashades']['ckan_web']['email_domain']
	})
	action :create
end

node.default['datashades']['auditd']['rules'].push(config_file)

cookbook_file "#{virtualenv_dir}/bin/activate_this.py" do
	source 'activate_this.py'
	owner service_name
	group service_name
	mode "0755"
end

#
# Initialise data
#

log "#{DateTime.now}: Initialising CKAN database"
execute "Init CKAN DB" do
	user "root"
	command "#{ckan_cli} db init 2>&1 >> '#{shared_fs_dir}/private/ckan_db_init.log.tmp' && mv '#{shared_fs_dir}/private/ckan_db_init.log.tmp' '#{shared_fs_dir}/private/ckan_db_init.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_db_init.log" }
end

execute "Update DB schema" do
	user service_name
	group service_name
	command "#{ckan_cli} db upgrade"
end

bash "Create CKAN Admin user" do
	user "root"
	code <<-EOS
		#{ckan_cli} user add sysadmin password="#{node['datashades']['ckan_web']['adminpw']}" email="#{node['datashades']['ckan_web']['adminemail']}" 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp"
		#{ckan_cli} sysadmin add sysadmin 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp" && mv "#{shared_fs_dir}/private/ckan_admin.log.tmp" "#{shared_fs_dir}/private/ckan_admin.log"
	EOS
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_admin.log"}
end

include_recipe "datashades::ckanweb-deploy-exts"

# Just in case something created files as root
execute "Refresh virtualenv ownership round2" do
	command "chown -RH ckan:ckan #{virtualenv_dir}"
end

# Prepare front-end CSS and JavaScript
# This needs to be after any extensions since they may affect the result.
bash "Create front-end resources" do
	user service_name
	group service_name
	code <<-EOS
		if (#{ckan_cli} front-end-build --help) then
			#{ckan_cli} front-end-build
		fi
	EOS
end

# Ensure our translation is compiled even if it's fuzzy
execute "Compile locale translation" do
	user service_name
	group service_name
	cwd install_dir
	command "#{virtualenv_dir}/bin/python setup.py compile_catalog -f --locale en_AU"
end

# Configure CKAN log processing
cookbook_file "/etc/logrotate.d/ckan" do
    source "ckan-logrotate"
end
