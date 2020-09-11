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

service_name = 'solr'
account_name = service_name

# Create solr group and user so they're allocated a UID and GID clear of OpsWorks managed users
#
group account_name do
	action :create
	gid 1001
end

user account_name do
	comment "Solr User"
	home "/home/#{account_name}"
	shell "/bin/bash"
	action :create
	uid 1001
	gid 1001
end

app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}-solr*").first
solr_version = app['app_source']['url'][/\/solr-([^\/]+)[.]zip$/, 1]
installed_solr_version = "/opt/solr-#{solr_version}"

unless ::File.identical?(installed_solr_version, "/opt/solr")
    solr_artefact = "#{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip"

    remote_file "#{solr_artefact}" do
        source app['app_source']['url']
    end

    # Would use archive_file but Chef client is not new enough
    execute "Extract #{service_name} #{solr_version}" do
        command "unzip -u -q #{solr_artefact} -d /tmp/solr"
    end

    service "solr" do
        action [:stop]
    end

    # wipe old properties so we can install the right version
    file "/etc/default/solr.in.sh" do
        action :delete
    end

    execute "Recover backed up start properties" do
        cwd "#{installed_solr_version}/bin"
        command "mv solr.in.sh.orig solr.in.sh"
        only_if { ::File.exist? "#{installed_solr_version}/bin/solr.in.sh.orig" }
    end

    execute "install #{service_name} #{solr_version}" do
        cwd "/tmp/solr/solr-#{solr_version}"
        command "./bin/install_solr_service.sh #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip -f"
    end
end

extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

# move Solr off root disk
efs_data_dir = "/data/#{service_name}"
var_data_dir = "/var/#{service_name}"
var_log_dir = "/var/#{service_name}/logs"
if extra_disk_present then
    real_data_dir = "#{extra_disk}/#{service_name}_data"
    real_log_dir = "#{extra_disk}/#{service_name}"
else
    real_data_dir = efs_data_dir
    real_log_dir = var_log_dir
end

directory real_data_dir do
    owner account_name
    group "ec2-user"
    mode "0775"
    action :create
end

if not ::File.identical?(real_data_dir, var_data_dir) then
    service service_name do
        action [:stop]
    end
    # transfer existing contents to target directory
    execute "rsync -a #{efs_data_dir}/ #{real_data_dir}/" do
        only_if { ::File.directory? efs_data_dir }
    end
    execute "rsync -a #{var_data_dir}/ #{real_data_dir}/" do
        only_if { ::File.directory? var_data_dir }
    end
    directory "#{var_data_dir}" do
        recursive true
        action :delete
    end
end

link var_data_dir do
    to real_data_dir
    ignore_failure true
end

link "/var/log/#{service_name}" do
    to real_data_dir
    ignore_failure true
end

# move logs off root disk

directory real_log_dir do
    owner account_name
    group "ec2-user"
    mode "0775"
    action :create
end

if not ::File.identical?(real_log_dir, var_log_dir) then
    service service_name do
        action [:stop]
    end
    # transfer existing contents to target directory
    execute "rsync -a #{var_log_dir}/ #{real_log_dir}/" do
        only_if { ::File.directory? var_log_dir }
    end
    directory "#{var_log_dir}" do
        recursive true
        action :delete
    end
end

link var_log_dir do
    to real_log_dir
    ignore_failure true
end

# move logs from EFS to extra EBS volume, if any
efs_log_dir = "#{efs_data_dir}/logs"
if not ::File.identical?(efs_log_dir, var_log_dir) then
    service service_name do
        action [:stop]
    end
    # transfer existing contents to target directory
    execute "rsync -a #{efs_log_dir}/ #{var_log_dir}/" do
        only_if { ::File.directory? efs_log_dir }
    end
    directory "#{efs_log_dir}" do
        recursive true
        action :delete
    end
end

link efs_log_dir do
    to var_log_dir
    ignore_failure true
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
