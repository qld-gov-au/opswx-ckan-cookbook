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

require 'date'

include_recipe "datashades::default"
include_recipe "datashades::ckanparams"

# Install CKAN services and dependencies
#
log "#{DateTime.now}: Installing packages required for CKAN"
node['datashades']['ckan_web']['packages'].each do |p|
	package p
end


# Install packages that have different names on different systems
node['datashades']['ckan_web']['alternative_packages'].each do |p|
	bash "Install one of #{p}" do
		code <<-EOS
			if (yum info "#{p[0]}"); then
				yum install -y "#{p[0]}"
			else
				yum install -y "#{p[1]}"
			fi
		EOS
	end
end

log "#{DateTime.now}: Creating accounts and directories for CKAN"

# Create CKAN Group
#
group "ckan" do
	action :create
	gid '2000'
	members "ec2-user"
	not_if { ::File.directory? "/home/ckan" }
end

# Create CKAN User
#
user "ckan" do
	comment "CKAN User"
	home "/home/ckan"
	shell "/sbin/nologin"
	action :create
	uid '2000'
	group 'ckan'
	not_if { ::File.directory? "/home/ckan" }
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
include_recipe "datashades::ckan-efs-setup"

#
# Set up Python virtual environment
#

log "#{DateTime.now}: Creating Python virtual environment for CKAN"
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
		owner 'ckan'
	end
else
	real_virtualenv_dir = virtualenv_dir
end

bash "Create CKAN Default Virtual Environment" do
	code <<-EOS
		PATH="$PATH:/usr/local/bin"
		virtualenv #{real_virtualenv_dir}
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

datashades_move_and_link "#{virtualenv_dir}/lib" do
	target "#{virtualenv_dir}/lib64"
	owner 'ckan'
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

# Add Bash alias to automatically use 'ckan' account for Git commands
if not system("grep 'alias git=' ~/.bash_profile")
    execute "Add CKAN Git alias to Bash" do
        command <<-EOS
            echo "alias git='sudo -u ckan git'" >> ~/.bash_profile
        EOS
    end
end
