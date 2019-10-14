#
# Author:: Carl Antuar (<carl.antuar@qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: httpd-efs-setup
#
# Updates DNS and mounts whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2019, Queensland Government
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

# Update EFS Data directory for Apache logging
#
include_recipe "datashades::efs-setup"

httpd_log_dir = "/var/log/httpd/#{node['datashades']['sitename']}"

# Clean up any symlink from prior cookbook versions

bash "Archive remaining logs" do
	user "root"
	cwd "/"
	code <<-EOS
		TIMESTAMP=`date +'%s'`
		for logfile in `ls #{httpd_log_dir}/*log`; do
			mv "$logfile" "$logfile.$TIMESTAMP"
			gzip "$logfile.$TIMESTAMP"
		done
		/usr/local/bin/archive-logs.sh httpd
	EOS
	only_if { ::File.symlink? "#{httpd_log_dir}" }
end
file "#{httpd_log_dir}" do
	action :delete
	only_if { ::File.symlink? "#{httpd_log_dir}" }
end

data_paths =
{
	"/var/log/httpd" => 'apache',
	"/var/log/httpd/#{node['datashades']['sitename']}" => 'apache'
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
