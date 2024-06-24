#
# Install batch layer requirements for CKAN
# Currently it has no special requirements, just installing CKAN.
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


include_recipe "datashades::default"

include_recipe "datashades::ckan-setup"

extra_disk = "/mnt/local_data"
if ::File.directory?(extra_disk) then
    swap_file = "#{extra_disk}/swapfile_2g"
    bash "Add swap disk" do
        code <<-EOS
            dd if=/dev/zero of=#{swap_file} bs=1024 count=2M
            chmod 0600 #{swap_file}
            mkswap #{swap_file}
        EOS
        not_if { ::File.exist?(swap_file) }
    end

    execute "Enable swap disk" do
        command "swapon -s | grep '^#{swap_file} ' || swapon #{swap_file}"
    end
end
