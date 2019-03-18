#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default-configure
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

# Run updateDNS script
#
execute 'update dns' do
	command	'/sbin/updatedns'
	user 'root'
	group 'root'
	not_if { ! ::File.directory? "/sbin/updatedns" }
end

# Update custom auditd rules
#
template '/etc/audit/rules.d/link.rules' do
	source 'auditd.rules.erb'
	owner 'root'
end

# Remove unwanted cron job from previous script versions
#
file '/etc/cron.daily/manageadmins' do
	action :delete
end

service 'sendmail' do
	action [:stop, :disable]
end

service 'aws-smtp-relay' do
	action [:enable, :restart]
end
