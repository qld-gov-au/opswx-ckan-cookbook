#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-gfs-setup
#
# Updates DNS and mounts whenever instance leaves or enters the online state or EIP/ELB config changes
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

# Setup GFS directories
#
paths = 
{
	"/data/gfs"
	"/var/shared_content" => 'apache', 
	"/var/www/sites" => 'apache', 
	"/var/log/nginx/#{node['datashades']['sitename']}" => 'nginx', 
	"/var/log/httpd/#{node['datashades']['sitename']}" => 'apache'
}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
	  owner dir_owner
	  group 'ec2-user'
	  mode '0775'
	  recursive true
	  action :create
	end
end

# Mount GFS volume
# 
mount "/data/gfs" do
	device "#{node['datashades']['version']}gfs1.#{node['datashades']['tld']}:/gv0" 
	fstype "glusterfs"
	options "defaults,_netdev,log-file=/var/log/gluster.log"
	action [:mount, :enable]
end

links = 
{ 
	"/var/shared_content" => "/data/gfs/shared_content",  
	"/var/log/nginx/#{node['datashades']['sitename']}" => "/data/gfs/logs/#{node['datashades']['sitename']}_nginx",
	"/var/log/httpd/#{node['datashades']['sitename']}" => "/data/gfs/logs/#{node['datashades']['sitename']}_apache"
}

links.each do |link_target, link_source|
	link link_target do
		to link_source
		link_type :symbolic
	end
end	


