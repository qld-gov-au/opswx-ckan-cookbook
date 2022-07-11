#
# Install batch job supervisor for CKAN
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

include_recipe "datashades::ckan-setup"
include_recipe "datashades::ckanbatch-efs-setup"

# Installing via yum gives initd integration, but has import problems.
# Installing via pip fixes the import problems, but doesn't provide the integration.
# So we do both.
execute "pip --cache-dir=/tmp/ install supervisor"

bash "Enable Supervisor file inclusions" do
	user "root"
	code <<-EOS
		SUPERVISOR_CONFIG=/etc/supervisord.conf
		if [ -f "$SUPERVISOR_CONFIG" ]; then
			mkdir -p /etc/supervisor/conf.d
			grep '/etc/supervisor/conf.d/' $SUPERVISOR_CONFIG && exit 0
			echo '[include]' >> $SUPERVISOR_CONFIG
			echo 'files = /etc/supervisor/conf.d/*.conf' >> $SUPERVISOR_CONFIG
		fi
	EOS
end

# Configure either initd or systemd
if ::File.exist? "/etc/init.d/supervisord" then
	# Managed processes sometimes don't shut down properly on daemon stop,
	# leaving them 'orphaned' and resulting in duplicates.
	# Work around by issuing a stop command to the children first.
	execute "Stop children on supervisord stop" do
		command <<-'SED'.strip + " /etc/init.d/supervisord"
			sed -i 's/^\(\s*\)\(killproc\)/\1timeout 10s supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; \2/'
		SED
	end
else
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
end
