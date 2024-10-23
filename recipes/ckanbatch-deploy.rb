#
# Deploys OpsWorks CKAN App to jobs layer
#
# Copyright 2021, Queensland Government
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

include_recipe "datashades::ckan-deploy"

service_name = "ckan"
app = node['datashades']['ckan_web']['ckan_app']

config_dir = "/etc/ckan/default"
config_file = "#{config_dir}/production.ini"
shared_fs_dir = "/var/shared_content/#{app['shortname']}"
virtualenv_dir = "/usr/lib/ckan/default"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

# Setup Site directories
# In ckan-deploy
# paths = {
#     "/var/log/#{service_name}" => "#{service_name}",
#     "#{shared_fs_dir}" => "#{service_name}",
# }
#
# paths.each do |nfs_path, dir_owner|
#     directory nfs_path do
#       owner dir_owner
#       group "#{service_name}"
#       recursive true
#       mode '0775'
#       action :create
#     end
# end

#
# Create job worker config files.
#

if system('yum info supervisor')
    cookbook_file "/etc/supervisord.d/supervisor-ckan-worker.ini" do
        source "supervisor-ckan-worker.conf"
        owner "root"
        group "root"
        mode "0744"
    end
else
    # Create files with our preferred ownership to work around https://github.com/systemd/systemd/issues/14385
    execute "Start job worker log file" do
        user service_name
        group service_name
        command "touch /var/log/ckan/ckan-worker.log"
    end
    systemd_unit "ckan-worker.service" do
        content({
            Unit: {
                Description: 'CKAN default job worker',
                After: 'network-online.target'
            },
            Service: {
                User: service_name,
                ExecStart: '/usr/lib/ckan/default/bin/ckan_cli jobs worker',
                Restart: 'on-failure',
                StandardOutput: 'append:/var/log/ckan/ckan-worker.log',
                StandardError: 'append:/var/log/ckan/ckan-worker.log'
            },
            Install: {
                WantedBy: 'multi-user.target'
            }
        })
        action [:create]
    end
end

# Set up maintenance scripts needed for cron jobs

cookbook_file "/usr/local/bin/archive-resource-revisions.sql" do
    source "archive-resource-revisions.sql"
    owner "root"
    group "root"
    mode "0644"
end

cookbook_file "/usr/local/bin/archive-resource-revisions.sh" do
    source "archive-resource-revisions.sh"
    owner "root"
    group "root"
    mode "0755"
end

template "/usr/local/bin/pick-job-server.sh" do
    source "pick-job-server.sh.erb"
    owner "root"
    group "root"
    mode "0755"
end

template "/usr/local/bin/ckan-email-notifications.sh" do
    source "ckan-email-notifications.sh.erb"
    owner "root"
    group "root"
    mode "0755"
    variables({
        :app_name => app['shortname'],
        :app_url => node['datashades']['ckan_web']['site_domain']
    })
end

template "/usr/local/bin/redis-clear.py" do
    source "redis-clear.py.erb"
    owner "root"
    group "root"
    mode "0755"
end

template "/usr/local/bin/redis-backup.py" do
    source "redis-backup.py.erb"
    owner "root"
    group "root"
    mode "0755"
end

template "/usr/local/bin/ckan-monitor-job-queue.sh" do
    source 'ckan-monitor-job-queue.sh.erb'
    owner 'root'
    group 'root'
    mode '0755'
end

# Set up useful scripts for support staff

cookbook_file "/usr/local/bin/psql-env-ckan.sh" do
    source "psql-env-ckan.sh"
    owner "root"
    group "root"
    mode "0644"
end

cookbook_file "/usr/local/bin/psql-ckan.sh" do
    source "psql-ckan.sh"
    owner "root"
    group "root"
    mode "0644"
end
