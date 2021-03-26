#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
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

include_recipe "datashades::default-configure"
include_recipe "datashades::squid-configure"

# Fix Amazon PYTHON_INSTALL_LAYOUT so items are installed in sites/packages not distr/packages
#
bash "Fix Python Install Layout" do
    user 'root'
    code <<-EOS
    sed -i 's~setenv PYTHON_INSTALL_LAYOUT "amzn"~# setenv PYTHON_INSTALL_LAYOUT "amzn"~g' /etc/profile.d/python-install-layout.csh
    sed -i 's~export PYTHON_INSTALL_LAYOUT="amzn"~# export PYTHON_INSTALL_LAYOUT="amzn"~g' /etc/profile.d/python-install-layout.sh
    unset PYTHON_INSTALL_LAYOUT
    EOS
    not_if "grep '# export PYTHON_INSTALL_LAYOUT' /etc/profile.d/python-install-layout.sh"
end

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

cookbook_file "/etc/logrotate.d/ckan" do
    source "ckan-logrotate"
end

# Make any other instances aware of us
#
file "/data/#{node['datashades']['hostname']}" do
    content "#{node['datashades']['instid']}"
end
