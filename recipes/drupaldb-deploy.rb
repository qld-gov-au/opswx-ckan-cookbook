#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: drupaldb-deploy
#
# Initialises Drupal DB if it doesn't exist yet
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


include_recipe "datashades::mysql-deploy"

app = search("aws_opsworks_app", "shortname:*drupal*").first

# Create drupal database if it doesn't exist
#
bash 'createdb' do
	code <<-EOH	
	mysql -uroot -p"#{node['datashades']['mysql']['rootpw']}" -e "CREATE DATABASE #{node['datashades']['sitename']}; GRANT ALL ON #{node['datashades']['sitename']}.* TO 'drupal_dba'@'%' IDENTIFIED BY '#{node['datashades']['mysql']['userpw']}';"
		EOH
	not_if "mysql -u root -p#{node['datashades']['mysql']['rootpw']} -e 'use #{node['datashades']['sitename']};'"
end


