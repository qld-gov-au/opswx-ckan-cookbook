#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: datapusher-configure
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2019, Queensland Government
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

include_recipe "datashades::stackparams"

template "/etc/httpd/conf.d/datapusher.conf" do
	source "datapusher.conf"
	owner "root"
	group "root"
	mode "0644"
end

# Clean up any symlink from prior cookbook versions
file "/etc/ckan/datapusher_settings.py" do
	action :delete
	only_if { ::File.symlink? "/etc/ckan/datapusher_settings.py" }
end

cookbook_file "/etc/ckan/datapusher_settings.py" do
	source "datapusher_settings.py"
	owner "datapusher"
	group "datapusher"
	mode "0644"
end

include_recipe "datashades::httpd-configure"
