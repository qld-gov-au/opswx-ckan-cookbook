#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: nginx-setup
#
# Installs NGINX Web Server Role
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
log "Installing packages required for Nginx"
node['datashades']['nginx']['packages'].each do |p|
	package p
end

log "Creating directories required for Nginx"
include_recipe "datashades::nginx-efs-setup"

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
service 'nginx' do
	action [:enable, :start]
end
