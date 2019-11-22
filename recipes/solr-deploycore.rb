#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: deploy-drupaldb
#
# Downloads and installs Apache Solr to Datashades OpsWorks Solr layer
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

ckan = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first

solr_core_dir="/data/solr/data/#{ckan['shortname']}"

# Create Solr core directory
#
directory "#{solr_core_dir}/data" do
	owner 'solr'
	group 'solr'
	recursive true
	mode '0775'
	action :create
end

# Create Solr core properties file
#
template "#{solr_core_dir}/core.properties" do
	source 'solr-ckan-core.erb'
	owner 'solr'
	group 'solr'
	mode '0755'
	variables({
		:app_name =>  ckan['shortname']
	})
end

# Copy and install Solr core conf
#
cookbook_file "#{Chef::Config[:file_cache_path]}/solr_core_config.zip" do
	source "ckan_solr_conf.zip"
end

execute 'Unzip Core Config' do
	user 'root'
	command "unzip -u -q -o #{Chef::Config[:file_cache_path]}/solr_core_config.zip -d #{solr_core_dir}"
end

service "solr" do
	action [:restart]
end

