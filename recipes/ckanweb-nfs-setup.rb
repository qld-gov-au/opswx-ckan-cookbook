#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-nfs-setup
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

# Setup NFS directories
#
paths = 
{
	"/var/shared_content" => 'apache', 
	"/var/www/sites" => 'apache', 
	"/var/log/nginx/#{node['ld']['sitename']}" => 'nginx', 
	"/var/log/httpd/#{node['ld']['sitename']}" => 'apache'
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

# Mount NFS volumes
# 
mounts = 
{ 
	"/var/shared_content" => "#{node['ld']['version']}nfs.#{node['ld']['tld']}:/data/nfs/shared_content",  
	"/var/log/nginx/#{node['ld']['sitename']}" => "#{node['ld']['version']}nfs.#{node['ld']['tld']}:/data/nfs/logs/#{node['ld']['sitename']}_nginx",
	"/var/log/httpd/#{node['ld']['sitename']}" => "#{node['ld']['version']}nfs.#{node['ld']['tld']}:/data/nfs/logs/#{node['ld']['sitename']}_apache"
}

mounts.each do |mount_point, mount_device|
	mount mount_point do
		device mount_device 
		fstype "nfs"
		options "rw,hard,intr"
		action [:mount, :enable]
	end
end	


