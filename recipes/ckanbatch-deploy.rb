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

include_recipe "datashades::stackparams"
include_recipe "datashades::ckan-deploy"

service_name = "ckan"
app = node['datashades']['ckan_app']

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

cookbook_file "/etc/supervisord.d/supervisor-ckan-worker.ini" do
    source "supervisor-ckan-worker.conf"
    owner "root"
    group "root"
    mode "0744"
end

# Set up maintenance cron jobs

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

# Remove unwanted cron job
file '/etc/cron.daily/ckan-tracking-update' do
    action :delete
end
#
# # Remove unwanted cron job from higher environments
# file '/etc/cron.hourly/ckan-tracking-update' do
#     action :delete
#     not_if { node['datashades']['version'] == 'DEV' || node['datashades']['version'] == 'TEST' }
# end

# Only set cron job for lower environments
file '/etc/cron.hourly/ckan-tracking-update' do
    content "/usr/local/bin/pick-job-server.sh && #{ckan_cli} tracking update >/dev/null 2>&1\n"
    mode '0755'
    owner "root"
    group "root"
    only_if { node['datashades']['version'] == 'DEV' || node['datashades']['version'] == 'TEST' }
end

# Run tracking update at 8:30am everywhere
file "/etc/cron.d/ckan-tracking-update" do
    content "30 8 * * * root /usr/local/bin/pick-job-server.sh && #{ckan_cli} tracking update >/dev/null 2>&1\n"
    mode '0644'
    owner "root"
    group "root"
end

file "/etc/cron.hourly/ckan-email-notifications" do
    content "/usr/local/bin/pick-job-server.sh && /usr/local/bin/ckan-email-notifications.sh > /dev/null 2>&1\n"
    mode '0755'
    owner "root"
    group "root"
end

file "/etc/cron.daily/ckan-revision-archival" do
    content "/usr/local/bin/pick-job-server.sh && /usr/local/bin/archive-resource-revisions.sh >/dev/null 2>&1\n"
    mode '0755'
    owner "root"
    group "root"
end

service "supervisord restart" do
    service_name "supervisord"
    action [:stop, :start]
end
