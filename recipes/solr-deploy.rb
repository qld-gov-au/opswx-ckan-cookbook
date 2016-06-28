#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-deploy
#
# Deploy Solr service to Solr layer
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

unless (::File.directory?("/data/solr"))
	app = search("aws_opsworks_app", 'shortname:*solr*').first
	
	remote_file "#{Chef::Config[:file_cache_path]}/solr.zip" do
		source app['app_source']['url']
	end
	
	bash "install solr" do
		user "root"
		code <<-EOS
		unzip -u -q #{Chef::Config[:file_cache_path]}/solr.zip -d /tmp/solr
		solrvers=$(ls /tmp/solr/ | grep 'solr-' | tr -d 'solr-') 
		mv #{Chef::Config[:file_cache_path]}/solr.zip #{Chef::Config[:file_cache_path]}/solr-${solrvers}.zip
		cd /tmp/solr/solr-${solrvers} 
		/tmp/solr/solr-${solrvers}/bin/install_solr_service.sh #{Chef::Config[:file_cache_path]}/solr-${solrvers}.zip
		mv /var/solr /data/
		
		maxhosts=#{node['datashades']['zk']['maxhosts']}
		zkhosts=""
		for (( sid=1; sid<=${maxhosts}; sid++ ))
		do
			zkhosts+="#{node['datashades']['version']}zk${sid}.#{node['datashades']['tld']}:2181,"
		done
		zkhostlist=$(echo ${zkhosts%?})
		sed -i "s~#ZK_HOST=\"\"~ZK_HOST=\"${zkhostlist}\"~" /etc/default/solr.in.sh
		
		solrid=$(cat /etc/solrid)
		sed -i "s~#SOLR_HOST=\"192.168.1.1\"~SOLR_HOST=\"#{node['datashades']['version']}${solrid}.#{node['datashades']['tld']}\"~" /etc/default/solr.in.sh
		
		EOS
		not_if { ::File.directory? "/data/solr" }
	end
	
	link "/var/solr" do
	 to "/data/solr"
	 link_type :symbolic
	end
	
	service "solr" do
		action [:enable, :start]
	end
end

include_recipe "datashades::solr-deploycore"
