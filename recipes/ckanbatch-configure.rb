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

service "supervisord" do
    action [:stop, :start]
end

service "httpd" do
    action [:stop, :disable]
end

template "/usr/local/bin/ckan-monitor-job-queue.sh" do
    source 'ckan-monitor-job-queue.sh.erb'
    owner 'root'
    group 'root'
    mode '0755'
end

file "/etc/cron.d/ckan-worker" do
    content "*/5 * * * * ckan /usr/local/bin/pick-job-server.sh && /usr/local/bin/ckan-monitor-job-queue.sh >/dev/null 2>&1\n"
    mode '0644'
end

# Make any other instances aware of us
#
file "/data/#{node['datashades']['hostname']}" do
    content "#{node['datashades']['instid']}"
end
