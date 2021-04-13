#
# Installs prerequisites for CKAN itself.
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

include_recipe "datashades::default"

# Install CKAN services and dependencies
#
node['datashades']['ckan_web']['packages'].each do |p|
	package p
end

# Create CKAN Group
#
group "ckan" do
	action :create
	gid '1000'
end

# Create CKAN User
#
user "ckan" do
	comment "CKAN User"
	home "/home/ckan"
	shell "/sbin/nologin"
	action :create
	uid '1000'
	group 'ckan'
end

# Explicitly set permissions on ckan directory so it's readable by Apache
#
directory '/home/ckan' do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
end

directory '/usr/lib/ckan' do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
end

# Set up shared directories
#
include_recipe "datashades::efs-setup"

#
# Set up Python virtual environment
#

execute "Install Python Virtual Environment" do
	command "pip --cache-dir=/tmp/ install virtualenv"
end

virtualenv_dir = "/usr/lib/ckan/default"
extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk
if extra_disk_present then
	real_virtualenv_dir = "#{extra_disk}/ckan_venv"

	datashades_move_and_link virtualenv_dir do
		target real_virtualenv_dir
	end
else
	real_virtualenv_dir = virtualenv_dir
end

bash "Create CKAN Default Virtual Environment" do
	code <<-EOS
		/usr/bin/virtualenv --no-site-packages #{real_virtualenv_dir}
		chown -R ckan:ckan #{real_virtualenv_dir}
	EOS
	not_if { ::File.directory? "#{real_virtualenv_dir}/bin" }
end

directory real_virtualenv_dir do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	recursive true
end

bash "Fix VirtualEnv lib issue" do
	user "ckan"
	group "ckan"
	cwd "#{virtualenv_dir}"
	code <<-EOS
		mv -f lib/python2.7/site-packages lib64/python2.7/
		rm -rf lib
		ln -sf lib64 lib
	EOS
	not_if { ::File.symlink? "#{virtualenv_dir}/lib" }
end

#
# Create CKAN configuration directory
#

directory "#{virtualenv_dir}/etc" do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
end

directory "/etc/ckan" do
	owner 'ckan'
	group 'ckan'
	mode '0755'
	action :create
	recursive true
end

link "/etc/ckan/default" do
	to "#{virtualenv_dir}/etc"
	link_type :symbolic
end
