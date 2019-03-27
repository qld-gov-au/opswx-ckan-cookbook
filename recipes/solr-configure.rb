#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-configure
#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2016, Link Digital
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

include_recipe "datashades::default-configure"

template "/usr/local/sbin/archive-solr-logs.sh" do
	source "archive-solr-logs.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.daily/archive-solr-logs-to-s3" do
	content "/usr/local/sbin/archive-solr-logs.sh 2>&1 >/dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end

service "solr" do
	action [:start]
end
