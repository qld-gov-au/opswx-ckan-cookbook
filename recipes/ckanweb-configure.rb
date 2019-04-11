#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-configure
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
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

include_recipe "datashades::default-configure"

# Fix Amazon PYTHON_INSTALL_LAYOUT so items are installed in sites/packages not distr/packages
#
bash "Fix Python Install Layout" do
	user 'root'
	code <<-EOS
	sed -i 's~setenv PYTHON_INSTALL_LAYOUT "amzn"~# setenv PYTHON_INSTALL_LAYOUT "amzn"~g' /etc/profile.d/python-install-layout.csh
	sed -i 's~export PYTHON_INSTALL_LAYOUT="amzn"~# export PYTHON_INSTALL_LAYOUT="amzn"~g' /etc/profile.d/python-install-layout.sh
	unset PYTHON_INSTALL_LAYOUT
	EOS
	not_if "grep '# export PYTHON_INSTALL_LAYOUT' /etc/profile.d/python-install-layout.sh"
end

include_recipe "datashades::httpd-configure"
include_recipe "datashades::nginx-configure"
service 'php-fpm-5.5' do
	action [:restart]
end

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:ckan-#{node['datashades']['version']}*").first
end

paster = "/usr/lib/ckan/default/bin/paster --plugin=ckan"
config_file = "/etc/ckan/default/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"

# Update tracking data
#
execute "Tracking update" do
	user "root"
	command "#{paster} tracking update -c #{config_file} 2>&1 >> '#{shared_fs_dir}/private/tracking-update.log.tmp' && mv '#{shared_fs_dir}/private/tracking-update.log.tmp' '#{shared_fs_dir}/private/tracking-update.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/tracking-update.log" }
end

# Update the Solr search index if needed
execute "Build search index" do
	user "root"
	command "#{paster} search-index rebuild -r -o -c #{config_file} 2>&1 > '#{shared_fs_dir}/private/solr-index-build.log'"
end

# Make any other instances aware of us
#
file "/data/#{node['datashades']['hostname']}" do
	content "#{node['datashades']['instid']}"
end
