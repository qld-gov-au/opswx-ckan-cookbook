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

include_recipe "datashades::stackparams"

service_name = "ckan"

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:#{service_name}-#{node['datashades']['version']}*").first
end

config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"
virtualenv_dir = "/usr/lib/ckan/default"

# Setup Site directories
#
paths = {
	"#{shared_fs_dir}/ckan_storage" => 'apache',
	"#{shared_fs_dir}/ckan_storage/storage" => 'apache',
	"#{shared_fs_dir}/ckan_storage/resources" => 'apache'
}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
	  owner dir_owner
	  group "#{service_name}"
	  recursive true
	  mode '0775'
	  action :create
	end
end

#
# Install CKAN source
#

include_recipe "datashades::ckan-deploy"
include_recipe "datashades::ckanweb-deploy-theme"

# app_url == Domains[0] is used for site_url, email domain defaults to public_tld if email_domain is not injected via attributes/ckan.rb
# # Update the CKAN site_url with the best public domain name we can find.
# # Best is a public DNS alias pointing to CloudFront.
# # Next best is the CloudFront distribution domain.
# # Use the load balancer address if there's no CloudFront.
# #
# app_url = app['domains'][0]
# bash "Detect public domain name" do
# 	user "#{service_name}"
# 	code <<-EOS
# 		cloudfront_domain=$(aws cloudfront list-distributions --query "DistributionList.Items[].{DomainName: DomainName, OriginDomainName: Origins.Items[].DomainName}[?contains(OriginDomainName, '#{app_url}')] | [0].DomainName" --output json | tr -d '"')
# 		if [ "$cloudfront_domain" != "null" ]; then
# 			public_name="$cloudfront_domain"
# 			zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['public_tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
# 			record_name=$(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --query "ResourceRecordSets[?AliasTarget].{Name: Name, Target: AliasTarget.DNSName}[?contains(Target, '$cloudfront_domain')] | [0].Name" --output json |tr -d '"' |sed 's/[.]$//')
# 			if [ "$record_name" != "null" ]; then
# 				public_name="$record_name"
# 				sed -i "s|^smtp[.]mail_from\s*=\([^@]*\)@.*$|smtp.mail_from=\1@$public_name|" #{config_file}
# 			fi
# 		fi
# 		if [ ! -z "$public_name" ]; then
# 			sed -i "s|^ckan[.]site_url\s*=.*$|ckan.site_url=https://$public_name/|" #{config_file}
# 		fi
# 	EOS
# end

#
# Clean up
#

# Just in case something created files as root
execute "Refresh virtualenv ownership" do
	user "root"
	group "root"
	command "chown -R ckan:ckan #{virtualenv_dir}"
end

#
# Create Apache config files
#

template "#{config_dir}/apache.wsgi" do
	source 'apache.wsgi.erb'
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
		:app_url => app['domains'][0],
		:domains => app['domains']
	})
	action :create
end

#
# Create NGINX Config files
#

node.override['datashades']['app']['locations'] = "location ~ ^#{node['datashades']['ckan_web']['endpoint']} { proxy_pass http://localhost:8000; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; }"

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
	action :create
end

node.default['datashades']['auditd']['rules'].push("/etc/nginx/conf.d/#{node['datashades']['sitename']}-#{app['shortname']}.conf")
