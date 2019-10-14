#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-efs-setup
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

# Update EFS Data directory for CKAN
#
include_recipe "datashades::httpd-efs-setup"

nginx_log_dir = "/var/log/nginx/#{node['datashades']['sitename']}"

# Clean up any symlink from prior cookbook versions

bash "Archive remaining logs" do
	user "root"
	cwd "/"
	code <<-EOS
		TIMESTAMP=`date +'%s'`
		for logfile in `ls #{nginx_log_dir}/*log`; do
			mv "$logfile" "$logfile.$TIMESTAMP"
			gzip "$logfile.$TIMESTAMP"
		done
		/usr/local/bin/archive-logs.sh nginx
	EOS
	only_if { ::File.symlink? "#{nginx_log_dir}" }
end
file "#{nginx_log_dir}" do
	action :delete
	only_if { ::File.symlink? "#{nginx_log_dir}" }
end

data_paths =
{
	"/data/shared_content" => 'apache',
	"/data/sites" => 'apache',
	"/var/log/nginx" => 'nginx',
	"/var/log/nginx/#{node['datashades']['sitename']}" => 'nginx'
}

data_paths.each do |data_path, dir_owner|
	directory data_path do
	  owner dir_owner
	  group 'ec2-user'
	  mode '0775'
	  recursive true
	  action :create
	end
end

link_paths =
{
	"/var/shared_content" => '/data/shared_content',
	"/var/www/sites" => '/data/sites'
}

link_paths.each do |link_path, source_path|
	link link_path do
		to source_path
		link_type :symbolic
	end
end
