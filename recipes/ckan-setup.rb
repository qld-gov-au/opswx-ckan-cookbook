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
include_recipe "datashades::ckanparams"

# Install CKAN services and dependencies
#
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

# Installing Supervisor via yum gives initd integration, but has import problems.
# Installing via pip fixes the import problems, but doesn't provide the integration.
# So we do both.
execute "pip --cache-dir=/tmp/ install supervisor"

bash "Configure Supervisord" do
	user "root"
	cwd "/etc"
	code <<-EOS
		SUPERVISOR_CONFIG=supervisord.conf
		if ! [ -f "$SUPERVISOR_CONFIG" ]; then
			exit 0
		fi

		# configure Unix socket path
		UNIX_SOCKET=/var/tmp/supervisor.sock
		DEFAULT_UNIX_SOCKET=/var/run/supervisor/supervisor[.]sock
		if (grep "$DEFAULT_UNIX_SOCKET" $SUPERVISOR_CONFIG); then
			# if default config exists, update it
			sed -i "s|$DEFAULT_UNIX_SOCKET|$UNIX_SOCKET|g" $SUPERVISOR_CONFIG
		fi
		if ! (grep "unix_http_server" $SUPERVISOR_CONFIG); then
			# if no config exists, add it
			echo '[unix_http_server]' >> $SUPERVISOR_CONFIG
			echo "file = $UNIX_SOCKET" >> $SUPERVISOR_CONFIG
		fi
		if ! (grep "rpcinterface:supervisor" $SUPERVISOR_CONFIG); then
			echo '[rpcinterface:supervisor]' >> $SUPERVISOR_CONFIG
			echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> $SUPERVISOR_CONFIG
		fi

		# configure file inclusions
		SUPERVISOR_CONFIG_D=supervisord.d
		mkdir -p $SUPERVISOR_CONFIG_D

		LEGACY_SUPERVISOR_CONFIG_D="/etc/supervisor/conf.d/[*][.]conf"
		if (grep "$LEGACY_SUPERVISOR_CONFIG_D" $SUPERVISOR_CONFIG); then
			# if legacy config exists, update it
			sed -i "s|$LEGACY_SUPERVISOR_CONFIG_D|$SUPERVISOR_CONFIG_D/*.ini|g" $SUPERVISOR_CONFIG
		elif ! (grep "$SUPERVISOR_CONFIG_D" $SUPERVISOR_CONFIG); then
			# if no config exists, add it
			echo '[include]' >> $SUPERVISOR_CONFIG
			echo "files = $SUPERVISOR_CONFIG_D/*.ini" >> $SUPERVISOR_CONFIG
		fi
	EOS
end

# Configure either initd or systemd
if system('which systemctl')
	systemd_unit "supervisord.service" do
		content({
			Unit: {
				Description: 'Supervisor process control system for UNIX',
				Documentation: 'http://supervisord.org',
				After: 'network.target'
			},
			Service: {
				ExecStart: '/usr/bin/supervisord -n -c /etc/supervisord.conf',
				ExecStop: 'timeout 10s /usr/bin/supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; /usr/bin/supervisorctl $OPTIONS shutdown',
				ExecReload: '/usr/bin/supervisorctl $OPTIONS reload',
				KillMode: 'process',
				Restart: 'on-failure',
				RestartSec: '20s'
			},
			Install: {
				WantedBy: 'multi-user.target'
			}
		})
		action [:create, :enable]
	end
else
	# Managed processes sometimes don't shut down properly on daemon stop,
	# leaving them 'orphaned' and resulting in duplicates.
	# Work around by issuing a stop command to the children first.
	execute "Stop children on supervisord stop" do
		command <<-'SED'.strip + " /etc/init.d/supervisord"
			sed -i 's/^\(\s*\)\(killproc\)/\1timeout 10s supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; \2/'
		SED
	end
end
