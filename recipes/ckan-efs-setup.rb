# Sets up EFS and EBS directories needed by all layers.
# This includes creating the logging directory /var/log/ckan
# and ensuring that /var/shared_content points to the EFS.
# If possible, it will move logs off the root disk.
#
# Copyright 2022, Queensland Government
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

include_recipe "datashades::efs-setup"

link_paths =
{
    "/var/shared_content" => '/data/shared_content',
}

link_paths.each do |link_path, source_path|
    datashades_move_and_link(link_path) do
        target source_path
    end
end

service_name = "ckan"

var_log_dir = "/var/log/#{service_name}"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

if extra_disk_present then
    real_log_dir = "#{extra_disk}/#{service_name}"

    datashades_move_and_link(var_log_dir) do
        target real_log_dir
        client_service "supervisord"
        owner service_name
    end
else
    real_log_dir = var_log_dir
end

directory real_log_dir do
    owner service_name
    group 'ec2-user'
    mode '0755'
    recursive true
end
