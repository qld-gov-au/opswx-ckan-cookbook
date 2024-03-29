#
# Moves a directory to a new location and leaves a symlink behind.
# If the new location already exists, the contents will be merged,
# with the moved files taking priority.
# If the old and new locations do not exist, the link will be created at
# the old location, but will point to nothing.
#
# Copyright 2021, Queensland Government
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

# Directory to move
property :source, String, name_property: true
# Location to move to
property :target, String
# Optional: operating system account that should own the directory
property :owner, [String, nil]
# Optional: service to stop before attempting the move
property :client_service, [String, nil], default: nil

action :create do
	if not ::File.identical?(new_resource.source, new_resource.target) then
		if new_resource.client_service then
			service "Stop #{new_resource.client_service} before moving #{new_resource.source}" do
				service_name new_resource.client_service
				action [:stop]
			end
		end

		# transfer existing contents to target directory
		execute "rsync -a #{new_resource.source}/ #{new_resource.target}/" do
			only_if { ::File.directory? new_resource.source }
		end

		execute "Ensure correct ownership of #{new_resource.target}" do
			command "chown -RH #{new_resource.owner}:#{new_resource.owner} #{new_resource.target}"
			ignore_failure true
			only_if { new_resource.owner and ::File.directory? new_resource.target }
		end

		directory "#{new_resource.source}" do
			recursive true
			action :delete
		end
	end

	link new_resource.source do
		to new_resource.target
		ignore_failure true
	end
end
