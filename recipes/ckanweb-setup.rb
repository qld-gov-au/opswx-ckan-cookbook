#
# Creates web server for CKAN
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


include_recipe "datashades::default"

# Install CKAN services and dependencies
#
node['datashades']['ckan_web']['packages'].each do |p|
    package p
end

include_recipe "datashades::httpd-efs-setup"
include_recipe "datashades::ckanweb-efs-setup"
include_recipe "datashades::nginx-setup"
include_recipe "datashades::ckan-setup"

httpd_conf_dir = "/etc/httpd"

# Change Apache default port to 8000 and fix access to /
#
bash "Change Apache config" do
    user 'root'
    group 'root'
    cwd httpd_conf_dir
    code <<-EOS
    sed -i 's~Listen 80~Listen 8000~g' conf/httpd.conf
    sed -i '/<Directory /{n;n;s/Require all denied/# Require all denied/}' conf/httpd.conf
    EOS
    not_if "grep 'Listen 8000' #{httpd_conf_dir}/conf/httpd.conf"
end

# Drop Apache modules that we don't need as they're dead weight
# and points of vulnerability.
#
directory "#{httpd_conf_dir}/conf.disabled" do
    owner 'root'
    mode '0755'
    action :create
end

directory "#{httpd_conf_dir}/conf.modules.disabled" do
    owner 'root'
    mode '0755'
    action :create
end

execute "Remove unused Apache config" do
    cwd "#{httpd_conf_dir}/conf.d"
    command "mv php-* php.* ../conf.disabled/ || echo 'Config already disabled'"
end

execute "Remove unused Apache modules" do
    cwd "#{httpd_conf_dir}/conf.modules.d"
    command "mv *-dav.conf *-lua.conf *-php.conf* *-proxy.conf ../conf.modules.disabled/ || echo 'Module(s) already disabled'"
end

# Enable Apache service
#
service 'httpd' do
    action [:enable]
end
