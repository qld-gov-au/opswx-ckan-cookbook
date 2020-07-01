#
# Author:: Carl Antuar (<carl.antuar@qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: nginx-efs-setup
#
# Sets up EFS and EBS directories and links for Nginx.
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

# Update EFS Data directory for Nginx logging
#
include_recipe "datashades::efs-setup"

service_name = 'nginx'

var_log_dir = "/var/log/#{service_name}"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

if extra_disk_present then
    real_log_dir = "#{extra_disk}/#{service_name}"
else
    real_log_dir = var_log_dir
end

directory "#{real_log_dir}/#{node['datashades']['sitename']}" do
    owner service_name
    group 'ec2-user'
    mode '0775'
    recursive true
    action :create
end

if not ::File.identical?(real_log_dir, var_log_dir) then
    service service_name do
        action [:stop]
    end
    # transfer existing contents to target directory
    execute "rsync -a #{var_log_dir}/ #{real_log_dir}/" do
        only_if { ::File.directory? var_log_dir }
    end
    directory "#{var_log_dir}" do
        recursive true
        action :delete
    end
end

link var_log_dir do
    to real_log_dir
    ignore_failure true
end
