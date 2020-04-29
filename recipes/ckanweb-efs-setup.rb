#
# Author:: Carl Antuar (<carl.antuar@qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-efs-setup
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

# Update EFS Data directory for CKAN
#
include_recipe "datashades::httpd-efs-setup"

extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

data_paths =
{
    "/data/shared_content" => 'apache',
    "/data/sites" => 'apache'
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

service 'nginx' do
    action [:stop]
end
execute "Stop job worker" do
    command "supervisorctl stop ckan-worker:ckan-worker-00"
end
for service_name in ['nginx', 'ckan'] do
    var_log_dir = "/var/log/#{service_name}"

    if extra_disk_present then
        real_log_dir = "#{extra_disk}/#{service_name}"
    else
        real_log_dir = var_log_dir
    end

    directory real_log_dir do
          owner service_name
          group 'ec2-user'
          mode '0775'
          recursive true
          action :create
    end

    if real_log_dir != var_log_dir then
        if ::File.directory? var_log_dir and not ::File.symlink? var_log_dir then
            # Directory under /var/log/ is not a link;
            # transfer contents to target directory and turn it into one
            execute "Move existing #{service_name} logs to extra EBS volume" do
                command "mv -n #{var_log_dir}/* #{real_log_dir}/; find #{var_log_dir} -maxdepth 1 -type l -delete; rmdir #{var_log_dir}"
            end
        end
        link var_log_dir do
            to real_log_dir
        end
    end
end
