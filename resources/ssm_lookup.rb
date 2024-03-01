#
# Looks up a value from SSM Parameter Store and populates a Chef node
# if the value was found.
#
# If the value does not exist or is not accessible, does nothing.
#
# Copyright 2024, Queensland Government
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

# SSM parameter key to look up
property :ssm_key, String, name_property: true
# The Chef node path to populate.
# Eg to write the value to node['datashades']['foo']['baz']
# you would pass in ['datashades', 'foo', 'baz']
property :chef_path, Array
# Optional: The SSM region to search, defaults to node['datashades']['region']
property :region, [String, nil], default: nil

action :create do
    region = new_resource.region
    if not region then
        region = node['datashades']['region']
    end

    value = `aws ssm get-parameter --region "#{region}" --name "#{new_resource.ssm_key}" --query "Parameter.Value" --with-decryption --output text`
    if value and not value.empty? then
        target_node = node
        *parent, key = new_resource.chef_path
        for node_name in parent
            target_node = target_node[node_name]
        end
        target_node.override[key] = value
    end
end
