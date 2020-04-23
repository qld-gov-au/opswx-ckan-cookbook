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

service_name = 'solr'

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

unless (::File.directory?("/opt/solr-#{solr_version}") and ::File.symlink?("/opt/solr") and ::File.readlink("/opt/solr").eql? "/opt/solr-#{solr_version}")
	remote_file "#{Chef::Config[:file_cache_path]}/solr.zip" do
		source app['app_source']['url']
	end

	bash "install #{service_name} #{solr_version}" do
		user "root"
		code <<-EOS
		unzip -u -q #{Chef::Config[:file_cache_path]}/solr.zip -d /tmp/solr
		mv #{Chef::Config[:file_cache_path]}/solr.zip #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip
		cd /tmp/solr/solr-#{solr_version}
		/tmp/solr/solr-#{solr_version}/bin/install_solr_service.sh #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip -f
		EOS
	end
end

unless (::File.directory?("/data/#{service_name}"))

	bash 'initialize solr data' do
		user "root"
		code "mv /var/solr /data/"
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

var_log_dir = "/var/log/#{service_name}"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

if extra_disk_present then
    real_log_dir = "#{extra_disk}/#{service_name}"
else
    real_log_dir = var_log_dir
end

directory real_log_dir do
    owner "solr"
    group "ec2-user"
    mode "0775"
    action :create
end

if real_log_dir != var_log_dir then
    if ::File.directory? var_log_dir and not ::File.symlink? var_log_dir then
        # Directory under /var/log/ is not a link;
        # transfer contents to target directory and turn it into one
        service "#{service_name}" do
            action [:stop]
        end
        execute "Move existing #{service_name} logs from /var/log/ to extra EBS volume" do
            command "mv #{var_log_dir}/* #{real_log_dir}/; rmdir #{var_log_dir}"
        end
    end
    link var_log_dir do
        to real_log_dir
    end
end

efs_log_dir = "/data/solr/logs"
if ::File.directory? efs_log_dir and not ::File.symlink? efs_log_dir then
    # Directory under /data/ is not a link;
    # transfer contents to target directory and turn it into one
    service service_name do
        action [:stop]
    end
    execute "Move existing #{service_name} logs from EFS to /var/log/" do
        command "mv #{efs_log_dir}/* #{var_log_dir}/; rmdir #{efs_log_dir}"
    end
end

link efs_log_dir do
    to var_log_dir
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
