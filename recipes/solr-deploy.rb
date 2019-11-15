#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-deploy
#
# Deploy Solr service to Solr layer
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

# Create solr group and user so they're allocated a UID and GID clear of OpsWorks managed users
#
group "solr" do
	action :create
	gid 1001
end

# Create Solr User
#
user "solr" do
	comment "Solr User"
	home "/home/solr"
	shell "/bin/bash"
	action :create
	uid 1001
	gid 1001
end

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}-solr*").first
download_url = app['app_source']['url']
solr_version = download_url[/\/solr-([^\/]+)[.]zip$/, 1]
Chef::Log.info("Solr version is #{solr_version}")
unless (::File.directory?("/opt/solr-#{solr_version}") and ::File.symlink?("/opt/solr") and ::File.readlink("/opt/solr").eql? "/opt/solr-#{solr_version}")
	remote_file "#{Chef::Config[:file_cache_path]}/solr.zip" do
		source app['app_source']['url']
	end

	bash "install solr" do
		user "root"
		code <<-EOS
		mkdir -p /home/solr
		unzip -u -q #{Chef::Config[:file_cache_path]}/solr.zip -d /tmp/solr
		mv #{Chef::Config[:file_cache_path]}/solr.zip #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip
		cd /tmp/solr/solr-#{solr_version}
		/tmp/solr/solr-#{solr_version}/bin/install_solr_service.sh #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip -f
		EOS
	end
end

unless (::File.directory?("/data/solr"))

	bash 'initialize solr data' do
		user "root"
		code "mv /var/solr /data/"
		not_if { ::File.directory? "/data/solr" }
	end

	# if we have pre-existing config, just wipe the extra copy
	directory "/var/solr" do
		recursive true
		action :delete
	end

	link "/var/solr" do
		to "/data/solr"
		link_type :symbolic
	end

end

service "solr" do
	action [:enable, :restart]
end

efs_log_dir = "/data/solr/logs"
ebs_log_dir = "/var/log/solr"

# Just in case the symlink was broken eg when creating a new instance with existing EFS data
directory "#{ebs_log_dir}" do
	owner "solr"
	group "ec2-user"
	mode "0775"
	recursive true
	action :create
end

bash "Move logs to EBS" do
	user "root"
	code <<-EOS
		cp -rf #{efs_log_dir}/* #{ebs_log_dir}/.
		rm -rf #{efs_log_dir}
		ln -sn #{ebs_log_dir} #{efs_log_dir}
	EOS
	not_if { ::File.symlink?("#{efs_log_dir}") }
end

# Create Monit config file to restart Solr when port 8983 not available
# Solves instance start issue after Solr install when /data doesn't mount fast enough
#
cookbook_file '/etc/monit.d/solr.monitrc' do
	source 'solr.monitrc'
	owner 'root'
	group 'root'
	mode '0755'
end

include_recipe "datashades::solr-deploycore"
