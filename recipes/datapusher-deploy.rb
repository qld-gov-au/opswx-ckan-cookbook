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

#
# Install selected revision of CKAN DataPusher
#

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}-#{service_name}*").first
virtualenv_dir = "/usr/lib/ckan/#{service_name}"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

execute "Install app from source" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install -e 'git+#{app['app_source']['url']}@#{app['app_source']['revision']}#egg=#{service_name}'"
	not_if { ::File.directory? "#{install_dir}" }
end

apprevision = app['app_source']['revision']
execute "Check out selected revision" do
	user "#{service_name}"
	group "#{service_name}"
	cwd "#{install_dir}"
	# pull if we're checking out a branch, otherwise it doesn't matter
	command "git fetch; git checkout '#{apprevision}'; git pull || true"
	not_if apprevision.nil?
end

execute "Install Python dependencies" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install -r '#{install_dir}/requirements.txt'"
end

# The dateparser library defaults to month-first but is configurable.
# Unfortunately, simply toggling the day-first flag breaks ISO dates.
# See https://github.com/dateutil/dateutil/issues/402
execute "Patch date parser format" do
	user "#{service_name}"
	command <<-'SED'.strip + " #{virtualenv_dir}/lib/python2.7/site-packages/messytables/types.py"
		sed -i "s/^\(\s*\)return parser[.]parse(value)/\1for fmt in ['%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%S.%f']:\n\1    try:\n\1        return datetime.datetime.strptime(value, fmt)\n\1    except ValueError:\n\1        pass\n\1return parser.parse(value, dayfirst=True)/"
	SED
end

#
# Create DataPusher configuration files
#

# Clean up any symlink from prior cookbook versions
file "/etc/ckan/datapusher_settings.py" do
	action :delete
	only_if { ::File.symlink? "/etc/ckan/datapusher_settings.py" }
end

cookbook_file "/etc/ckan/datapusher_settings.py" do
	source "datapusher_settings.py"
	owner "#{service_name}"
	group "#{service_name}"
	mode "0644"
end

#
# Create Apache config files
#

template "/etc/httpd/conf.d/datapusher.conf" do
	source "datapusher.conf"
	owner "apache"
	group "apache"
	mode "0644"
end

link "/etc/ckan/#{service_name}.wsgi" do
	to "#{install_dir}/deployment/#{service_name}.wsgi"
end
