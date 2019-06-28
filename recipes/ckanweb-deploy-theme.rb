#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: deploy-ckanweb-theme
#
# Deploy CKAN theme files
#
# Copyright 2019, Queensland Government
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

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-theme-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:*-theme-#{node['datashades']['version']}*").first
end

if app
	site_dir = "/var/www/sites/#{node['datashades']['app_id']}-#{node['datashades']['version']}/"
	config_dir = "/etc/ckan/default"

	directory "#{site_dir}" do
		owner "ec2-user"
		group "apache"
		mode "0750"
	end

	# convert HTTP(S) URL to S3 URL
	s3_archive_url = app['app_source']['url'].sub(/https?:\/\/[^\/]*\//, 's3://')
	execute "Retrieve S3 archive" do
		user "ec2-user"
		group "apache"
		command "aws s3 cp #{s3_archive_url} /tmp/CKAN-theme.zip"
	end

	bash "Unzip theme" do
		user "ec2-user"
		group "apache"
		cwd "#{site_dir}"
		code <<-EOS
			mkdir -p staging backup
			rm -r staging/* backup/*
			(cd staging && unzip /tmp/CKAN-theme.zip)
			mv public templates backup/
			mv staging/* .
		EOS
	end

	bash "Configure legacy Bootstrap" do
		user "ckan"
		group "ckan"
		cwd "#{config_dir}"
		code <<-EOS
			sed -i "/^ckan.base_public_folder\s*=\s*public$/ s/$/-bs2/" production.ini
			sed -i "/^ckan.base_templates_folder\s*=\s*templates$/ s/$/-bs2/" production.ini
		EOS
	end


	#
	# Clean up
	#

	execute "Refresh theme ownership" do
		user "root"
		group "root"
		command "chown -R ec2-user:apache #{site_dir} && chmod -R '0750' #{site_dir}"
	end

end
