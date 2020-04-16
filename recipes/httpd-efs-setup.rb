#
# Author:: Carl Antuar (<carl.antuar@qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: httpd-efs-setup
#
# Updates DNS and mounts whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2020, Queensland Government
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

service_name = 'httpd'

var_log_dir = "/var/log/#{service_name}/#{node['datashades']['sitename']}"

if extra_disk_present then
    real_log_dir = "#{extra_disk}/#{service_name}/#{node['datashades']['sitename']}"
else
    real_log_dir = var_log_dir
end

data_paths =
{
    "#{var_log_dir}" => 'apache',
    "#{real_log_dir}" => 'apache'
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

if real_log_dir != var_log_dir then
    if ::File.directory? var_log_dir and not ::File.symlink? var_log_dir then
        # Directory under /var/log/ is not a link;
        # transfer contents to target directory and turn it into one
        service service_name do
            action [:stop]
        end
        execute "Move existing #{service_name} logs to extra EBS volume" do
            command "mv #{var_log_dir}/* #{real_log_dir}/; rmdir #{var_log_dir}"
        end
    end
    link var_log_dir do
        to real_log_dir
    end
end

