#
# Deploys OpsWorks CKAN App
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

service_name = "ckan"

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:#{service_name}-#{node['datashades']['version']}*").first
end

config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"
virtualenv_dir = "/usr/lib/ckan/default"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
paster = "#{virtualenv_dir}/bin/paster --plugin=#{service_name}"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

# Setup Site directories
#
paths = {
	"/var/log/#{service_name}" => "#{service_name}",
	"#{shared_fs_dir}" => "#{service_name}",
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

directory "#{shared_fs_dir}/private" do
	owner "root"
	mode '0700'
	action :create
end

# Get the version number from the app revision, by preference,
# or from the app URL if revision is not defined.
# Either way, ensure that the version number is stripped from the URL.
if app['app_source']['type'].eql? "git" then
	version = app['app_source']['revision']
end
apprelease = app['app_source']['url'].sub("#{service_name}/archive/", "#{service_name}.git@").sub('.zip', "")
urlrevision = apprelease[/@(.*)/].sub '@', ''
apprelease.sub!(/@(.*)/, '')
version ||= urlrevision
version ||= "master"

#
# Install selected revision of CKAN core
#

if (::File.exist? "#{install_dir}/requirements.txt") then
	if app['app_source']['type'].casecmp("git") == 0 then
		execute "Ensure correct CKAN Git origin" do
			user "#{service_name}"
			cwd "#{install_dir}"
			command "git remote set-url origin '#{apprelease}'"
		end
	end
else
	execute "Install CKAN #{version}" do
		user "#{service_name}"
		group "#{service_name}"
		command "#{pip} install -e 'git+#{apprelease}@#{version}#egg=#{service_name}'"
	end
end

bash "Check out #{version} revision of CKAN" do
	user "#{service_name}"
	group "#{service_name}"
	cwd "#{install_dir}"
	code <<-EOS
		# retrieve latest branch metadata
		git fetch origin '#{version}'
		# drop unversioned files
		git clean
		# make versioned files pristine
		git reset --hard
		git checkout '#{version}'
		# get latest changes if we're checking out a branch, otherwise it doesn't matter
		git pull
		# drop compiled files from previous branch
		find . -name '*.pyc' -delete
		# regenerate metadata
		#{virtualenv_dir}/bin/python setup.py develop
	EOS
end

execute "Install Python dependencies" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install -r '#{install_dir}/requirements.txt'"
end

execute "Install Raven Sentry client" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install --upgrade raven"
end

#
# Set up CKAN configuration files
#

template "#{config_file}" do
	source 'ckan_properties.ini.erb'
	owner "#{service_name}"
	group "#{service_name}"
	mode "0755"
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0],
		:src_dir => "#{virtualenv_dir}/src",
		:email_domain => node['datashades']['ckan_web']['email_domain']
	})
	action :create
end

node.default['datashades']['auditd']['rules'].push("#{config_file}")

cookbook_file "#{virtualenv_dir}/bin/activate_this.py" do
	source 'activate_this.py'
	owner "#{service_name}"
	group "#{service_name}"
	mode "0755"
end

link "#{config_dir}/who.ini" do
	to "#{install_dir}/who.ini"
	link_type :symbolic
end

#
# Initialise data
#

execute "Init CKAN DB" do
	user "root"
	command "#{paster} db init -c #{config_file} 2>&1 >> '#{shared_fs_dir}/private/ckan_db_init.log.tmp' && mv '#{shared_fs_dir}/private/ckan_db_init.log.tmp' '#{shared_fs_dir}/private/ckan_db_init.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_db_init.log" }
end

execute "Update DB schema" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{paster} db upgrade -c #{config_file}"
end

bash "Create CKAN Admin user" do
	user "root"
	code <<-EOS
		#{paster} --plugin=ckan user add sysadmin password="#{node['datashades']['ckan_web']['adminpw']}" email="#{node['datashades']['ckan_web']['adminemail']}" -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp"
		#{paster} --plugin=ckan sysadmin add sysadmin -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp" && mv "#{shared_fs_dir}/private/ckan_admin.log.tmp" "#{shared_fs_dir}/private/ckan_admin.log"
	EOS
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_admin.log"}
end

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
	user "#{service_name}"
	group "#{service_name}"
	command "#{paster} front-end-build -c #{config_file}"
end

