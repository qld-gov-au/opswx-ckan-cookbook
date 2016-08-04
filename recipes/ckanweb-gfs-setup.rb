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

service_name = 'gfs-client'

# Setup GlusterFS repo
#
bash "Setup #{service_name} repo" do
	user "root"
	code <<-EOS
		wget -P /etc/yum.repos.d http://download.gluster.org/pub/gluster/glusterfs/3.7/3.7.11/EPEL.repo/glusterfs-epel.repo
		sudo sed -i -e 's/epel-$releasever/epel-6/g' /etc/yum.repos.d/glusterfs-epel.repo
	EOS
end

# Install necessary packages
#
node['datashades'][service_name]['packages'].each do |p|
	package p
end

# Setup GFS directories
#
paths = 
{
	"/data/gfs" => 'root',
	"/var/www/sites" => 'apache'
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


