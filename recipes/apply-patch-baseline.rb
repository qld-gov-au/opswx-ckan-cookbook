#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: apply-patch-baseline
#
# Applies critical security patches, and then reboots if necessary.
# This should typically be run only after all other actions are complete.
#
# Copyright 2026, Queensland Government
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

# Run updateDNS script
#
bash 'Apply operating system patches' do
    user 'root'
    group 'root'
    code <<-EOH
        dnf upgrade-minimal --security -y
        dnf needs-restarting || reboot
    EOH
end
