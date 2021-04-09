# Sets up EFS and EBS directories and links for CKAN.
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

service_name = "ckan"

var_log_dir = "/var/log/#{service_name}"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

if extra_disk_present then
    real_log_dir = "#{extra_disk}/#{service_name}"
else
    real_log_dir = var_log_dir
end

datashades_move_and_link(var_log_dir) do
    target real_log_dir
    client_service "supervisord"
end

directory real_log_dir do
    owner service_name
    group 'ec2-user'
    mode '0755'
    recursive true
    action :create
end
