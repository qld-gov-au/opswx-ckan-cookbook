#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: deploy-ckanweb
#
# Deploys OpsWorks CKAN App to web layer
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


app = search("aws_opsworks_app", 'shortname:*ckan_*').first

# Define CKAN endpoint NGINX location directive 
#
node.override['datashades']['app']['locations'] = "location ~ ^#{node['datashades']['ckan_web']['endpoint']} { proxy_pass http://localhost:8000; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; }"					

# Create NGINX Config file
#
template "/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf" do
	source 'nginx.conf.erb'
	owner 'root'
	group 'root'
	mode '0755'
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0]
   		
	})
	not_if { node['datashades']['ckan_web']['endpoint'] != "/" }
	action :create_if_missing
end
	
# Setup Site directories
#
paths = {"/var/shared_content/#{app['shortname']}" => 'apache', "/etc/ckan/default" => 'root', "/var/shared_content/#{app['shortname']}/ckan_storage" => 'apache', "/var/log/nginx/#{app['shortname']}" => 'nginx', "/var/log/apache/#{app['shortname']}" => 'apache'}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
	  owner dir_owner
	  recursive true
	  mode '0775'
	  action :create
	end
end

apprelease = app['app_source']['url']
apprelease.sub! 'ckan/archive/', "ckan.git@" 			
apprelease.sub! '.zip', ""


# Install CKAN
#
unless (::File.exists?("/usr/lib/ckan/default/src/ckan/requirements.txt"))
	bash "Install CKAN" do
		user "root"
		code <<-EOS
			. /usr/lib/ckan/default/bin/activate
			pip install -e "git+#{apprelease}#egg=ckan"
			cd /usr/lib/ckan/default/src/ckan
			pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt
			deactivate
			. /usr/lib/ckan/default/bin/activate
			cd /usr/lib/ckan/default/src/ckan
			paster make-config ckan /etc/ckan/default/production.ini
			deactivate
			chown -R ckan:ckan /usr/lib/ckan
		EOS
	end

	template '/etc/ckan/default/production.ini' do
		source 'ckan_properties.ini.erb'
		owner 'root'
		group 'root'
		mode '0755'
		variables({
			:app_name =>  app['shortname'],
			:app_url => app['domains'][0]
		})
		action :create_if_missing		
	end

	bash "Init CKAN DB" do
		user "root"
		code <<-EOS
			mkdir -p /var/shared_content/"#{app['shortname']}"/private
			. /usr/lib/ckan/default/bin/activate
			cd /usr/lib/ckan/default/src/ckan
			paster db init -c /etc/ckan/default/production.ini > /var/shared_content/"#{app['shortname']}"/private/ckan_db_init.log
			deactivate
		EOS
		not_if { ::File.exists?"/var/shared_content/#{app['shortname']}/private/ckan_db_init.log" }	
	end

end

cookbook_file '/usr/lib/ckan/default/bin/activate_this.py' do
  source 'activate_this.py'
  owner 'ckan'
  group 'ckan'
  mode '0755'
end

link "/etc/ckan/default/who.ini" do
	to "/usr/lib/ckan/default/src/ckan/who.ini"
	link_type :symbolic
end

cookbook_file '/etc/ckan/default/apache.wsgi' do
	source 'apache.wsgi'
	owner 'root'
	group 'root'
	mode '0755'
end

template '/etc/httpd/conf.d/ckan.conf' do
	source 'apache_ckan.conf.erb'
	owner 'apache'
	group 'apache'
	mode '0755'
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0]
	})
	action :create_if_missing		
end


# Install CKAN extensions
#
#include_recipe "linksoe::deploy-ckanweb-exts"

# Restart Web services to enable new configurations
#
services = [ 'php-fpm-5.5', 'nginx', 'httpd' ]

services.each do |servicename|
	service servicename do
		action [:restart]
	end
end
