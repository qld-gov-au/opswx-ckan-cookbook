#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: deploy-drupalweb
#
# Deploys OpsWorks Drupal App to web layer
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

app = search("aws_opsworks_app", "shortname:*drupal*").first

# Deploy drupal based on source type
#
# git 		means existing app to be checked out
# archive	means fresh install from drupal distro
#
if app['app_source']['type'] == 'git'

	pub_key = app['app_source']['ssh_key']

	repo = "#{app['app_source']['url']}"
	repouser = (repourl.split"@")[0]
	repohost = (repourl.split"@")[1].split("/")[0]

	# Create GHE SSH entry to allow git operations via Apache php script
	#
	directory '/var/www/.ssh' do
	  owner 'apache'
	  group 'apache'
	  mode '0775'
	  action :create
	end

	file "/var/www/.ssh/#{node['datashades']['sitename']}-#{app['shortname']}.pem" do
		content "#{pub_key}"
		owner 'apache'
		group 'apache'
		mode '0600'
		action :create
		only_if { ! ::File.exist? "/var/www/.ssh/#{node['datashades']['sitename']}-#{app['shortname']}.pem" }
	end

	bash "Add GHE to known_hosts" do
		code <<-EOS
		ssh-keyscan -f /var/www/.ssh/known_hosts -H repohost >> /var/www/.ssh/known_hosts
		EOS
		user 'apache'
		group 'apache'
		only_if { ! ::File.exist? "/var/www/.ssh/known_hosts" }
	end

	bash "Create #{node['datashades']['sitename']}-#{app['shortname']} Config entry" do
		code <<-EOS
		echo -e "Host #{node['datashades']['sitename']}-#{app['shortname']}\r\n\tUser\t#{repouser}\r\n\tHostname\t#{repohost}\r\n\tIdentityFile\t/var/www/.ssh/#{node['datashades']['sitename']}-#{app['shortname']}.pem" >> /var/www/.ssh/config
		EOS
		not_if "grep -q 'Host #{node['datashades']['sitename']}-#{app['shortname']}' /var/www/.ssh/config"
	end

	repo.sub! "#{repouser}@#{repohost}", "#{node['datashades']['sitename']}-#{app['shortname']}"

	bash "Make target writable" do
		code <<-EOS
		chmod 755 -R /var/www/sites/"#{node['datashades']['sitename']}"
		EOS
		user 'root'
		only_if { ::File.exist? "/var/www/sites/#{node['datashades']['sitename']}/.git/config" }
	end

	git app['shortname'] do
		revision	app['app_source']['revision']
		destination "/var/www/sites/#{node['datashades']['sitename']}"
		checkout_branch app['app_source']['revision']
		enable_checkout false
		repository repo
		user 'apache'
		group 'apache'
	  	action :sync
	end

	bash "Make target unwritable by apache" do
		code <<-EOS
		chmod 575 -R /var/www/sites/"#{node['datashades']['sitename']}"
		EOS
		user 'root'
	end

	# Move files directory if it exists
	#
	bash "Move repo files directory" do
		code <<-EOS
		mv /var/www/sites/"#{node['datashades']['sitename']}"/sites/default/files /var/www/sites/"#{node['datashades']['sitename']}"/sites/default/files_repo
		EOS
		user 'root'
		only_if { ::File.directory? "/var/www/sites/#{node['datashades']['sitename']}/sites/default/files" }
	end
end


if "#{app['app_source']['type']}" == 'archive'

	# Download and Latest Drupal if it doesn't exist in the site directory (due to repo download)
	#
	unless (::File.exist?"/var/www/sites/#{node['datashades']['sitename']}/robots.txt")

		remote_file "#{Chef::Config[:file_cache_path]}/drupal.zip" do
			source app['app_source']['url']
		end

		# Create Drupal core web directory
		#
		directory "/var/www/sites/#{node['datashades']['sitename']}" do
		  owner 'apache'
		  group 'apache'
		  mode '0765'
		  action :create
		end

		# Unzip Drupal
		#
		bash "unzip drupal" do
			code <<-EOS
			unzip #{Chef::Config[:file_cache_path]}/drupal.zip -d /var/www/sites/#{node['datashades']['sitename']}/
			EOS
			user 'root'
		end

		bash "install drupal files" do
			code <<-EOS
			d7v=$(ls /var/www/sites/#{node['datashades']['sitename']}/ | grep 'drupal-' | tr -d 'drupal-')
			mv /var/www/sites/#{node['datashades']['sitename']}/drupal-${d7v}/* /var/www/sites/#{node['datashades']['sitename']}/
			rm -rf /var/www/sites/#{node['datashades']['sitename']}/drupal-${d7v}
			chmod -R 575 /var/www/sites/#{node['datashades']['sitename']}
			chown -R apache:apache /var/www/sites/#{node['datashades']['sitename']}
			EOS
			user 'root'
		end
	end

	bash "cleanup_drupal" do
		code <<-EOS
		mv /var/www/sites/#{node['datashades']['sitename']}/robots.txt /var/www/sites/#{node['datashades']['sitename']}/robots.txm
		rm -rf /var/www/sites/#{node['datashades']['sitename']}/*.txt
		mv /var/www/sites/#{node['datashades']['sitename']}/robots.txm /var/www/sites/#{node['datashades']['sitename']}/robots.txt
		EOS
		user 'root'
		only_if { ::File.exist? "/var/www/sites/#{node['datashades']['sitename']}/INSTALL.txt" }
	end
end

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
end

# Setup Site directories
#
paths = { "/var/shared_content/#{node['datashades']['sitename']}-#{app['shortname']}/files" => 'apache', "/var/shared_content/#{node['datashades']['sitename']}-#{app['shortname']}/private" => 'apache', "/var/log/nginx/#{node['datashades']['sitename']}" => 'nginx'}

paths.each do |nfs_path, dir_owner|
	directory nfs_path do
		owner dir_owner
		group 'apache'
		mode '0775'
		action :create
		recursive true
	end
end

# Link drupal default/files to shared_content folder on NFS
#
link "/var/www/sites/#{node['datashades']['sitename']}/sites/default/files" do
	to "/var/shared_content/#{node['datashades']['sitename']}-#{app['shortname']}/files"
	owner 'apache'
	group 'apache'
	mode '0775'
	link_type :symbolic
end

cookbook_file "/var/www/sites/#{node['datashades']['sitename']}/sites/default/files/.htaccess" do
	source "drupal_files.htaccess"
	owner 'root'
	group 'root'
	mode '0600'
end

# Create/Update settings.php
#
template "/var/www/sites/#{node['datashades']['sitename']}/sites/default/settings.php" do
  source 'drupal_settings.php.erb'
  owner 'apache'
  group 'apache'
  mode '0755'
  variables({
    	:app_name =>  app['shortname'],
		:app_url => app['domains'][0],
		:app_db => "#{node['datashades']['sitename']}"

  		})
  only_if "grep -q 'Drupal' /var/www/sites/#{node['datashades']['sitename']}/index.php"
end

# Start php-fpm if it isn't already running
#
service "php-fpm-5.5" do
	action :start
end

# Restart nginx so the new web app starts serving
#
service "nginx" do
	action :restart
end

# Install drush
#
bash "Install drush" do
	code <<-EOS
	php -r "readfile('http://files.drush.org/drush.phar');" > /usr/local/bin/drush
	chmod +x /usr/local/bin/drush
	EOS
	user 'root'
	not_if { ::File.exist? "/usr/local/bin/drush" }
end

# Do site setup if required
#
bash "Drush site install" do
	user 'root'
	cwd "/var/www/sites/#{node['datashades']['sitename']}"
	code <<-EOS
	echo "y" | /usr/local/bin/drush site-install standard --site-name="#{node['datashades']['sitename']}" --account-name=admin --account-pass="#{node['datashades']['drupal_web']['adminpw']}" --db-url="mysql://drupal_dba:#{node['datashades']['mysql']['userpw']}@#{node['datashades']['version']}mysql.#{node['datashades']['tld']}/#{node['datashades']['sitename']}"
	touch "/var/www/sites/#{node['datashades']['sitename']}/sites/default/siteinstalled"
	EOS
	not_if { ::File.exist? "/var/www/sites/#{node['datashades']['sitename']}/sites/default/siteinstalled" }
end

