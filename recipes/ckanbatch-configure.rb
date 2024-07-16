#
# Start/restart background job services.
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

include_recipe "datashades::ckan-configure"

virtualenv_dir = "/usr/lib/ckan/default"
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"

if not system('yum info supervisor')
    service "ckan-worker" do
        action [:enable, :start]
    end

    bash "Enable extra job queues if available" do
        code <<-EOS
            UNITS="ckan-worker-priority ckan-worker-bulk ckan-worker-harvest-fetch ckan-worker-harvest-gather"
            for UNIT_NAME in $UNITS; do
                if (systemctl -a |grep "$UNIT_NAME"); then
                    systemctl enable "$UNIT_NAME"
                    systemctl start "$UNIT_NAME"
                fi
            done
        EOS
    end
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

file "/etc/cron.d/ckan-worker" do
    content "*/5 * * * * root /usr/local/bin/pick-job-server.sh && /usr/local/bin/ckan-monitor-job-queue.sh >/dev/null 2>&1\n"
    mode '0644'
end

# Only set cron job for lower environments
file '/etc/cron.hourly/ckan-tracking-update' do
    content "/usr/local/bin/pick-job-server.sh && #{ckan_cli} tracking update >/dev/null 2>&1\n"
    mode '0755'
    owner "root"
    group "root"
    only_if { node['datashades']['version'] == 'DEV' || node['datashades']['version'] == 'TEST' }
end

# Make any other instances aware of us
#
execute "/usr/local/bin/pick-job-server.sh || true"
