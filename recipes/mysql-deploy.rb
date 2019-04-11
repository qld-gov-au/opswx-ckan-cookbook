#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: mysql-deploy
#
# Initialises MySQL install
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

service_name = 'mysql'

# Exports need to be defined here so sitename is set correctly
#
node.default['datashades'][service_name]['host'] = "#{node['datashades']['version']}#{service_name}.#{node['datashades']['tld']}"

service 'mysqld' do
	action [:enable, :start]
end

# Run through initial setup if root password never set
#
unless (::File.exist?("/data/mysql"))

	# Stop MySQL to move directory
	#
	service "mysqld" do
		action :stop
	end

	# Move mysql data directory to data location
	#
	bash 'mv_mysql' do
	  code <<-EOH
		mv /var/lib/mysql /data/
		ln -sf /data/mysql/ /var/lib/mysql
	    EOH
	  not_if { ::File.exist?("/data/mysql") }
	end

	service "mysqld" do
		action :start
	end
end

cookbook_file "/etc/my.cnf" do
	source "my.cnf"
	owner 'root'
	group 'root'
	mode '0755'
	action :create_if_missing
end

# Do mysqladmin init
#
bash 'mysqladmin' do
  code <<-EOH
	mysqladmin -uroot password "#{node['datashades']['mysql']['rootpw']}"
	mysql -uroot -p"#{node['datashades']['mysql']['rootpw']}" -e 'DROP DATABASE test;'
    EOH
  only_if "mysql -u root -e 'show databases;'"
end

