#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: zookeeper-deploy
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

unless (::File.directory?("/opt/zookeeper"))
	app = search("aws_opsworks_app", 'shortname:*zookeeper*').first
	
	remote_file "#{Chef::Config[:file_cache_path]}/zookeeper.tar.gz" do
		source app['app_source']['url']
	end
	
	bash "install zookeeper" do
		user "root"
		code <<-EOS
		tar -xvzf #{Chef::Config[:file_cache_path]}/zookeeper.tar.gz
		vers=$(ls #{Chef::Config[:file_cache_path]} | grep 'zookeeper-' | tr -d 'zookeeper-') 
		mv #{Chef::Config[:file_cache_path]}/zookeeper-${vers} /opt/
		ln -sf /opt/zookeeper-${vers} /opt/zookeeper
		mkdir -p /data/zookeeper/data
		ln -sf 	/data/zookeeper/data /opt/zookeeper/data
		cp /opt/zookeeper/conf/zoo_sample.cfg /opt/zookeeper/conf/zoo.cfg
		sed -i 's~dataDir=/tmp/zookeeper~dataDir=/opt/zookeeper/data~' /opt/zookeeper/conf/zoo.cfg	
		ln -sf /etc/zkid /opt/zookeeper/data/myid
		maxhosts= #{node['datashades']['zk']['maxhosts']}
		for sid in {1..${maxhosts}}
		do
			echo "server.${sid}=#{node['datashades']['version']}zk${sid}.#{node['datashades']['tld']}:2888:3888" >> /opt/zookeeper/conf/zoo.cfg
		done
		EOS
	end
end

execute 'Start Zookeeper'
	user 'root'
	command '/opt/zookeeper/bin/zkServer.sh start'
end
