#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: squid-configure
#
# Configures Squid proxy server to blacklist private addresses.
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

cookbook_file '/etc/squid/squid.conf' do
	source 'squid.conf'
	owner 'root'
	group 'root'
	mode '0755'
end

service "squid" do
	supports :restart => true, :reload => true, :status => true
	action [:enable, :start, :reload]
end
