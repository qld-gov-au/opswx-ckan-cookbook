#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: nginx-setup
#
# Installs NGINX and PHP-FPM Web Server Role
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

include_recipe "datashades::stackparams"

# Install NGINX packages
#
node['datashades']['nginx']['packages'].each do |p|
  package p
end

# Update php and nginx default config files
#
bash 'config_php' do
	code <<-EOH
		sed -i 's~127.0.0.1:9000~/tmp/phpfpm.sock~g' /etc/php-fpm-5.5.d/www.conf
		sed -i 's~nobody~/tmp/phpfpm.sock~g' /etc/php-fpm-5.5.d/www.conf
		sed -i 's~memory_limit = 128M~memory_limit = #{node['datashades']['nginx']['mem_limit']}~g' /etc/php-5.5.ini
		sed -i "s~post_max_size = 8M~post_max_size = #{node['datashades']['nginx']['maxdl']}~g" /etc/php-5.5.ini
		sed -i "s~upload_max_filesize = 2M~upload_max_filesize = #{node['datashades']['nginx']['maxdl']}~g" /etc/php-5.5.ini
		echo -e "listen.owner = nginx\nlisten.group = nginx" >> /etc/php-fpm-5.5.d/www.conf
		sed -i 's:default_server::g'  /etc/nginx/nginx.conf
	EOH
end

# Create self-signed temporary SSL cert for Datashades
#
bash 'install ssl certs' do
	user 'root'
	code <<-EOH
		openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/ssl/certs/wild."#{node['datashades']['tld']}".key -out /etc/ssl/certs/wild."#{node['datashades']['tld']}".crt -days 365 -subj "/C=AU/ST=ACT/L=Canberra/O=Datashades/CN=*.#{node['datashades']['tld']}"
	EOH
	not_if { ::File.exist?("/etc/ssl/certs/wild.#{node['datashades']['tld']}.crt") }
end

# Startup services
#
services = [ 'php-fpm-5.5', 'nginx']

services.each do |servicename|
	service servicename do
		action [:enable, :start]
	end
end

