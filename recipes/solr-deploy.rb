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

include_recipe "datashades::stackparams"

service_name = 'solr'
account_name = service_name
efs_data_dir = "/data/#{service_name}"
var_data_dir = "/var/#{service_name}"
var_log_dir = "/var/#{service_name}/logs"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

# Create solr group and user so they're allocated a UID and GID clear of OpsWorks managed users
#
group account_name do
    action :create
    gid 2001
end

if not system("grep '^#{account_name}:x:2001' /etc/passwd > /dev/null") then
    bash "Stop Solr processes before modifying account" do
        code <<-EOS
            ps -U solr -o pid= |xargs kill
            for i in {1..30}; do
                ps -U solr > /dev/null 2>&1 || break
                sleep 1
            done
        EOS
    end

    user account_name do
        comment "Solr User"
        home "/home/#{account_name}"
        manage_home true
        shell "/bin/bash"
        action :create
        uid 2001
        gid 2001
    end
end

core_name = "#{node['datashades']['app_id']}-#{node['datashades']['version']}"
solr_source = node['datashades']['solr_app']['app_source']['url']
solr_version = solr_source[/\/solr-([^\/]+)[.]zip$/, 1]
solr_path = "/opt/solr"
installed_solr_version = "#{solr_path}-#{solr_version}"
solr_environment_file = "/etc/default/solr.in.sh"

unless ::File.identical?(installed_solr_version, solr_path)
    solr_artefact = "#{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip"
    if extra_disk_present then
        working_dir = "#{extra_disk}/solr_install"
    else
        working_dir = "/tmp/solr_install"
    end

    directory working_dir do
        mode "0644"
        action :create
    end

    remote_file "#{solr_artefact}" do
        source solr_source
    end

    # Would use archive_file but Chef client is not new enough
    execute "Extract #{service_name} #{solr_version}" do
        command "unzip -u -q #{solr_artefact} -d #{working_dir}"
    end

    execute "solr stop before install" do
        user 'root'
        # Try multiple styles
        command "(supervisorctl status 'solr:*' && supervisorctl stop 'solr:*') || (systemctl status solr >/dev/null 2>&1 && systemctl stop solr) || (service solr status >/dev/null 2>&1 && service solr stop) || echo 'Unable to stop Solr, already stopped?'"
    end

    # wipe old properties so we can install the right version
    file solr_environment_file do
        action :delete
    end

    execute "Recover backed up start properties" do
        cwd "#{installed_solr_version}/bin"
        command "mv solr.in.sh.orig solr.in.sh"
        only_if { ::File.exist? "#{installed_solr_version}/bin/solr.in.sh.orig" }
    end

    execute "install #{service_name} #{solr_version}" do
        cwd "#{working_dir}/solr-#{solr_version}"
        command "./bin/install_solr_service.sh #{Chef::Config[:file_cache_path]}/solr-#{solr_version}.zip -f -n"
    end
end

# Replace legacy initd integration with supervisord
service "solr" do
    action [:disable]
end

cookbook_file "/etc/supervisord.d/supervisor-solr.ini" do
    source "supervisor-solr.conf"
    owner "root"
    group "root"
    mode "0744"
end

# Create management scripts

cookbook_file '/bin/updatedns' do
	source 'updatedns'
	owner 'root'
	group 'root'
	mode '0755'
end

template "/usr/local/bin/solr-env.sh" do
	source "solr-env.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

cookbook_file "/usr/local/bin/solr-healthcheck.sh" do
	source "solr-healthcheck.sh"
	owner "root"
	group "root"
	mode "0755"
end

cookbook_file "/usr/local/bin/toggle-solr-healthcheck.sh" do
	source "toggle-solr-healthcheck.sh"
	owner "root"
	group "root"
	mode "0755"
end

cookbook_file "/usr/local/bin/pick-solr-master.sh" do
	source "pick-solr-master.sh"
	owner "root"
	group "root"
	mode "0755"
end

cookbook_file "/usr/local/bin/solr-sync.sh" do
	source "solr-sync.sh"
	owner "root"
	group "root"
	mode "0755"
end

cookbook_file "/etc/logrotate.d/solr" do
	source "solr-logrotate"
end

# Patch vulnerable Log4J

log4j_version = '2.17.1'
for jar_type in ['1.2-api', 'api', 'core', 'slf4j-impl'] do
    log4j_artefact = "log4j-#{jar_type}"
    bash "Patch #{log4j_artefact} to version #{log4j_version}" do
        cwd "#{solr_path}/server/lib/ext"
        code <<-EOS
            ls #{log4j_artefact}-*.jar |grep -v '[-]#{log4j_version}.jar' |xargs rm
            curl -O -C - "https://repo1.maven.org/maven2/org/apache/logging/log4j/#{log4j_artefact}/#{log4j_version}/#{log4j_artefact}-#{log4j_version}.jar"
        EOS
    end
end

# move logs off root disk

if extra_disk_present then
    real_data_dir = "#{extra_disk}/#{service_name}_data"
    real_log_dir = "#{extra_disk}/#{service_name}"
else
    real_data_dir = efs_data_dir
    real_log_dir = var_log_dir
end

datashades_move_and_link(var_log_dir) do
    target real_log_dir
    client_service service_name
    owner service_name
end

datashades_move_and_link("/var/log/#{service_name}") do
    target real_log_dir
    client_service service_name
    owner service_name
end

directory real_log_dir do
    owner account_name
    group "ec2-user"
    mode "0755"
end

# move logs from EFS to extra EBS volume, if any

efs_log_dir = "#{efs_data_dir}/logs"
datashades_move_and_link(efs_log_dir) do
    target real_log_dir
    client_service service_name
    owner service_name
end

# move Solr core onto extra EBS disk

directory real_data_dir do
    owner account_name
    group "ec2-user"
    mode "0775"
    action :create
end

directory "#{efs_data_dir}/data/#{core_name}/data" do
    owner account_name
    group "ec2-user"
    mode "0775"
    action :create
    recursive true
end

# copy latest EFS contents
service service_name do
    action [:stop]
end
execute "rsync -a --delete #{efs_data_dir}/ #{real_data_dir}/" do
    only_if { ::File.directory? efs_data_dir }
end

datashades_move_and_link(var_data_dir) do
    target real_data_dir
    client_service service_name
    owner service_name
end

# Use find+exec instead of chown's recursive -R flag,
# so that we can exclude temporary snapshots.
execute "Ensure directory ownership is correct" do
    command "find #{efs_data_dir}/data/#{core_name} #{real_data_dir}/data/#{core_name} #{solr_environment_file} #{real_log_dir} |grep -vE 'snapshot|index' |xargs chown #{account_name}:ec2-user"
end

include_recipe "datashades::solr-deploycore"
