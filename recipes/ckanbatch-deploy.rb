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

service "supervisord" do
    action :stop
end

include_recipe "datashades::stackparams"
include_recipe "datashades::ckan-deploy"

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
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"
install_dir = "#{virtualenv_dir}/src/#{service_name}"

# Setup Site directories
#
paths = {
    "/var/log/#{service_name}" => "#{service_name}",
    "#{shared_fs_dir}" => "#{service_name}",
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
# Create job worker config files.
#

cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-worker.conf" do
    source "supervisor-ckan-worker.conf"
    owner "root"
    group "root"
    mode "0644"
end

service "supervisord" do
    action [:enable]
end

# Set up maintenance cron jobs

cookbook_file "/usr/local/bin/archive-resource-revisions.sql" do
    source "archive-resource-revisions.sql"
    owner "root"
    group "root"
    mode "0644"
end

cookbook_file "/usr/local/bin/archive-resource-revisions.sh" do
    source "archive-resource-revisions.sql"
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

# Remove unwanted cron job
file '/etc/cron.daily/ckan-tracking-update' do
    action :delete
end

# Remove unwanted cron job from higher environments
file '/etc/cron.hourly/ckan-tracking-update' do
    action :delete
    not_if { node['datashades']['version'] == 'DEV' || node['datashades']['version'] == 'TEST' }
end

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

# Run dataset require updates notifications at 7am and 7:15am on batch
if File.foreach(config_file).grep(/^\s*ckan[.]plugins\s*=.*\bdata_qld(_integration)?\b/).any?
    file "/etc/cron.d/ckan-dataset-notification-due" do
        content "00 7 * * MON root /usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-data-qld #{ckan_cli} send_email_dataset_due_to_publishing_notification >/dev/null 2>&1\n"\
                "15 7 * * MON root /usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-data-qld #{ckan_cli} send_email_dataset_overdue_notification >/dev/null 2>&1\n"
        mode '0644'
        owner "root"
        group "root"
    end
end

file "/etc/cron.hourly/ckan-email-notifications" do
    content "/usr/local/bin/pick-job-server.sh && curl -d '{}' #{app['domains'][0]}#{node['datashades']['ckan_web']['endpoint']}api/action/send_email_notifications > /dev/null 2>&1\n"
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
