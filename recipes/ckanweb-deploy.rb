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
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
paster = "#{virtualenv_dir}/bin/paster --plugin=#{service_name}"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

# Setup Site directories
#
paths = {
	"/var/log/#{service_name}" => "#{service_name}",
	"#{shared_fs_dir}" => "#{service_name}",
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

directory "#{shared_fs_dir}/private" do
	owner "root"
	mode '0700'
	action :create
end

apprelease = app['app_source']['url']

if app['app_source']['type'].eql? "git" then
	version = app['app_source']['revision']
else
	apprelease.sub! "#{service_name}/archive/", "#{service_name}.git@"
	apprelease.sub! '.zip', ""
	version = apprelease[/@(.*)/].sub! '@', ''
end

#
# Install selected revision of CKAN core
#

if (::File.exist? "#{install_dir}/requirements.txt") then
	if app['app_source']['type'].casecmp("git") == 0 then
		execute "Ensure correct Git origin" do
			user "#{service_name}"
			cwd "#{install_dir}"
			command "git remote set-url origin '#{app['app_source']['url']}'"
		end
	end
else
	execute "Install CKAN #{version}" do
		user "#{service_name}"
		group "#{service_name}"
		command "#{pip} install -e 'git+#{apprelease}#egg=#{service_name}'"
	end
end

bash "Check out selected revision" do
	user "#{service_name}"
	group "#{service_name}"
	cwd "#{install_dir}"
	# pull if we're checking out a branch, otherwise it doesn't matter
	code <<-EOS
		git fetch
		git reset --hard
		git checkout '#{version}'
		git pull
		find . -name '*.pyc' -delete
	EOS
end

execute "Install Python dependencies" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install -r '#{install_dir}/requirements.txt'"
end

execute "Install Raven Sentry client" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{pip} install --upgrade raven"
end

#
# Set up CKAN configuration files
#

template "#{config_file}" do
	source 'ckan_properties.ini.erb'
	owner "#{service_name}"
	group "#{service_name}"
	mode "0755"
	variables({
		:app_name =>  app['shortname'],
		:app_url => app['domains'][0],
		:email_domain => node['datashades']['ckan_web']['email_domain']
	})
	action :create
end

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

node.default['datashades']['auditd']['rules'].push("#{config_file}")

cookbook_file "#{virtualenv_dir}/bin/activate_this.py" do
	source 'activate_this.py'
	owner "#{service_name}"
	group "#{service_name}"
	mode "0755"
end

link "#{config_dir}/who.ini" do
	to "#{install_dir}/who.ini"
	link_type :symbolic
end

#
# Initialise data
#

execute "Init CKAN DB" do
	user "root"
	command "#{paster} db init -c #{config_file} 2>&1 >> '#{shared_fs_dir}/private/ckan_db_init.log.tmp' && mv '#{shared_fs_dir}/private/ckan_db_init.log.tmp' '#{shared_fs_dir}/private/ckan_db_init.log'"
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_db_init.log" }
end

execute "Update DB schema" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{paster} db upgrade -c #{config_file}"
end

bash "Create CKAN Admin user" do
	user "root"
	code <<-EOS
		#{paster} --plugin=ckan user add sysadmin password="#{node['datashades']['ckan_web']['adminpw']}" email="#{node['datashades']['ckan_web']['adminemail']}" -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp"
		#{paster} --plugin=ckan sysadmin add sysadmin -c #{config_file} 2>&1 >> "#{shared_fs_dir}/private/ckan_admin.log.tmp" && mv "#{shared_fs_dir}/private/ckan_admin.log.tmp" "#{shared_fs_dir}/private/ckan_admin.log"
	EOS
	not_if { ::File.exist? "#{shared_fs_dir}/private/ckan_admin.log"}
end

#
# Install CKAN extensions
#

include_recipe "datashades::ckanweb-deploy-exts"
include_recipe "datashades::ckanweb-deploy-theme"

#
# Clean up
#

# Just in case something created files as root
execute "Refresh virtualenv ownership" do
	user "root"
	group "root"
	command "chown -R ckan:ckan #{virtualenv_dir}"
end

# Prepare front-end CSS and JavaScript
# This needs to be after any extensions since they may affect the result.
execute "Create front-end resources" do
	user "#{service_name}"
	group "#{service_name}"
	command "#{paster} front-end-build -c #{config_file}"
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
# Create job worker config files
#

bash "Enable Supervisor file inclusions" do
	user "root"
	code <<-EOS
		SUPERVISOR_CONFIG=/etc/supervisord.conf
		if [ -f "$SUPERVISOR_CONFIG" ]; then
			grep '/etc/supervisor/conf.d/' $SUPERVISOR_CONFIG && exit 0
			mkdir -p /etc/supervisor/conf.d
			echo '[include]' >> $SUPERVISOR_CONFIG
			echo 'files = /etc/supervisor/conf.d/*.conf' >> $SUPERVISOR_CONFIG
		fi
	EOS
end

cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-worker.conf" do
	source "supervisor-ckan-worker.conf"
	owner "root"
	group "root"
	mode "0744"
end

cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-harvest-gather.conf" do
	source "supervisor-ckan-harvest-gather.conf"
	owner "root"
	group "root"
	mode "0744"
end

cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-harvest-fetch.conf" do
	source "supervisor-ckan-harvest-fetch.conf"
	owner "root"
	group "root"
	mode "0744"
end

service "supervisord" do
	action [:enable]
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

# Set up maintenance cron jobs

template "/usr/local/bin/pick-job-server.sh" do
	source "pick-job-server.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.daily/ckan-tracking-update" do
	content "/usr/local/bin/pick-job-server.sh && #{paster} tracking update -c #{config_file} 2>&1 >/dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.hourly/ckan-email-notifications" do
	content "/usr/local/bin/pick-job-server.sh && echo '{}' | #{paster} post -c #{config_file} /api/action/send_email_notifications 2>&1 > /dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.hourly/ckan-harvest-run" do
	content "/usr/local/bin/pick-job-server.sh && echo '{}' | #{paster} --plugin=ckanext-harvest harvester run -c #{config_file} 2>&1 > /dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end
