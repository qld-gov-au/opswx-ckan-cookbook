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

ckan = search("aws_opsworks_app", "shortname:*ckan_*").first

# Install Solr conf if it doesn't exist
#
unless (::File.directory?("/data/solr/data/#{ckan['shortname']}/conf"))

	# Create Solr core directory
	#
	directory "/data/solr/data/#{ckan['shortname']}/data" do
	  owner 'solr'
	  group 'solr'
	  recursive true
	  mode '0775'
	  action :create
	end
	
	# Create Solr core properties file
	#
	solr_node = 1;
	lazy { solr_node = IO.read("/etc/solrid") }
	template "/data/solr/data/#{ckan['shortname']}/core.properties" do
		  source 'solr-ckan-core.erb'
		  owner 'solr'
		  group 'solr'
		  mode '0755'
		  variables({
		   		:app_name =>  ckan['shortname'],
				:solr_node => solr_node
		 		})
		  
	end
	
	# Copy and install Solr core conf
	#
	cookbook_file "#{Chef::Config[:file_cache_path]}/solr_core_config.zip" do
		source "ckan_solr_conf.zip"
	end

	bash 'Unzip Core Config' do
	  code <<-EOS
	  unzip -u -q #{Chef::Config[:file_cache_path]}/solr_core_config.zip -d /data/solr/data/#{ckan['shortname']}	
	  EOS
	  not_if { ::File.directory? "/data/solr/data/#{ckan['shortname']}/conf" }	
	  user 'root'
	end

	service "solr" do
		action [:restart]
	end	
end

