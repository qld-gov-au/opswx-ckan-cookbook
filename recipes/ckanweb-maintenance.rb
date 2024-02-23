#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-maintenance
#
# Runs long tasks such as Solr index rebuilds. This is not run automatically.
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

include_recipe "datashades::stackparams"

ckan_app_name = "#{node['datashades']['app_id']}-#{node['datashades']['version']}"

ckan_cli = "/usr/lib/ckan/default/bin/ckan_cli"
config_file = "/etc/ckan/default/production.ini"
shared_fs_dir = "/var/shared_content/#{ckan_app_name}"

# Update tracking data
#
execute "Tracking update" do
	user "root"
	command "#{ckan_cli} tracking update 2>&1 >> '#{shared_fs_dir}/private/tracking-update.log.tmp' && mv '#{shared_fs_dir}/private/tracking-update.log.tmp' '#{shared_fs_dir}/private/tracking-update.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/tracking-update.log" }
end

# Update the Solr search index
execute "Build search index" do
	user "root"
	command "#{ckan_cli} search-index rebuild -r 2>&1 > '#{shared_fs_dir}/private/solr-index-build.log'"
end
