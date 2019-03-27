#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: datapusher-deploy
#
# Installs DataPusher service
#
# Copyright 2019, Queensland Government
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

service_name = "datapusher"

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

virtualenv_dir = "/usr/lib/ckan/#{service_name}"

bash "Create Virtual Environment" do
	user "root"
	code <<-EOS
		/usr/bin/virtualenv --no-site-packages "#{virtualenv_dir}"
		chown -R #{service_name}:#{service_name} "#{virtualenv_dir}"
	EOS
	not_if { ::File.directory? "#{virtualenv_dir}/bin" }
end

bash "Fix VirtualEnv lib issue" do
	user "#{service_name}"
	group "#{service_name}"
	cwd "#{virtualenv_dir}"
	code <<-EOS
	mv -f lib/python2.7/site-packages lib64/python2.7/
	rm -rf lib
	ln -sf lib64 lib
	EOS
	not_if { ::File.symlink? "#{virtualenv_dir}/lib" }
end

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}-#{service_name}*").first
install_dir = "#{virtualenv_dir}/src/#{service_name}"

execute "Install app from source" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{virtualenv_dir}/bin/pip install --cache-dir=/tmp/ -e 'git+#{app['app_source']['url']}@#{app['app_source']['revision']}#egg=#{service_name}'"
	not_if { ::File.directory? "#{install_dir}" }
end

execute "Install Python dependencies" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{virtualenv_dir}/bin/pip install --cache-dir=/tmp/ -r '#{install_dir}/requirements.txt'"
end

# The dateparser library defaults to month-first but is configurable
execute "Patch date parser format" do
	user "#{service_name}"
	command "sed -i 's/parser[.]parse(value)/parser.parse(value, dayfirst=True)/' #{virtualenv_dir}/lib/python2.7/site-packages/messytables/types.py"
end

directory "/etc/ckan" do
  owner "#{service_name}"
  group "#{service_name}"
  mode '0755'
  action :create
  recursive true
  # If we happen to be sharing the box with another CKAN virtualenv, don't steal ownership
  not_if { ::File.exist? "/etc/ckan" }
end

# Serve via Apache mod_wsgi
link "/etc/ckan/#{service_name}.wsgi" do
	to "#{install_dir}/deployment/#{service_name}.wsgi"
end

service "httpd" do
	action [:enable]
end
