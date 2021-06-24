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
include_recipe "datashades::efs-setup"

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
    datashades_move_and_link(link_path) do
        target source_path
    end
end

