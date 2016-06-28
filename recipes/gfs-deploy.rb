#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: gfs-deploy
#
# Creates GFS directories and exports GFS paths
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

# Exports need to be defined here so sitename is set correctly
#
node.default['datashades']['gfs']['exports'] = ["/data/gfs/shared_content", "/data/gfs/logs/#{node['datashades']['sitename']}_nginx", "/data/gfs/logs/#{node['datashades']['sitename']}_apache"]

# Create NFS directories
#
node['datashades']['gfs']['exports'].each do |path|
	directory path do
	  owner 'root'
	  group 'ec2-user'
	  mode '0775'
	  action :create
	  recursive true
	end
end

bash 'Create Gluster Volume' do
	code <<-EOS
	id=$(cat /etc/gfsid)
	if [ "$id" == "#{node['datashades']['gfs']['maxhosts']}" ]; then
		glusterstatus=$(gluster volume info)
		if [ glusterstatus == "No volumes present" ]; then
			gfs1 = "#{node['datashades']['version']}gfs1.#{node['datashades']['tld']}"
			gfs2 = "#{node['datashades']['version']}gfs1.#{node['datashades']['tld']}"
			gluster volume create gv0 replica 2 ${gfs1}:/data/gfs ${gfs2}:/data/gfs
			gluster volume start gv0
		fi
	fi
	EOS
end





