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

# Create ASG helper script
#
cookbook_file "/bin/updateasg" do
	source "updateasg"
	owner 'root'
	group 'root'
	mode '0755'
end

include_recipe "datashades::ckan-setup"

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

# Managed processes sometimes don't shut down properly on daemon stop,
# leaving them 'orphaned' and resulting in duplicates.
# Work around by issuing a stop command to the children first.
execute "Stop children on supervisord stop" do
	command <<-'SED'.strip + " /etc/init.d/supervisord"
		sed -i 's/^\(\s*\)\(killproc\)/\1timeout 10s supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; \2/'
	SED
end
