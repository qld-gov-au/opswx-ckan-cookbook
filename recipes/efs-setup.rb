#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: efs-setup
#
# Creates data directory and mounts EFS
#
# Copyright 2017, Link Digital
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

# Create and mount EFS Data directory
#

include_recipe "datashades::stackparams"

directory '/mnt/efs' do
  action :create
end

mount 'connect efs root' do
  device "#{node['datashades']['version']}efs.#{node['datashades']['tld']}:/"
  mount_point '/mnt/efs'
  fstype "nfs4"
  options "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2"
  action :mount
end

directory "/mnt/efs/#{node['datashades']['app_id']}" do
	owner 'ec2-user'
	group 'ec2-user'
	mode '0775'
  action :create
end

directory "/data" do
	owner 'ec2-user'
	group 'ec2-user'
	mode '0775'
	recursive true
	action :create
end

mount '/data' do
	device "#{node['datashades']['version']}efs.#{node['datashades']['tld']}:/#{node['datashades']['app_id']}"
	fstype "nfs4"
	options "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2"
	action [:mount, :enable]
end

mount 'disconnect efs root' do
  device "#{node['datashades']['version']}efs.#{node['datashades']['tld']}:/"
  mount_point '/mnt/efs'
  action :umount
end
