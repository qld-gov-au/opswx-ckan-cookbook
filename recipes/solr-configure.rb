#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-configure
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

service_name = 'solr'
efs_data_dir = "/data/#{service_name}"
core_name = "#{node['datashades']['app_id']}-#{node['datashades']['version']}"

execute "Add instance to Solr health check pool" do
	command "touch /data/solr-healthcheck_#{node['datashades']['hostname']}"
end

# Generate properties specific to this server
template "/usr/local/bin/solr-env.sh" do
	source "solr-env.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.d/solr-healthcheck" do
	content "* * * * * root /usr/local/bin/solr-healthcheck.sh > /dev/null 2>&1\n"
	mode "0644"
end

# copy latest EFS contents
service "Stop Solr if needed to load latest index" do
	service_name service_name
	action [:stop]
end
bash "Copy latest index from EFS" do
	user account_name
	code <<-EOS
		rsync -a --delete #{efs_data_dir}/ /var/#{service_name}
		CORE_DATA="/var/#{service_name}/data/#{core_name}/data"
		LATEST_INDEX=`ls -dtr $CORE_DATA/snapshot.* |tail -1`
		# If the latest snapshot is a readable tar archive, then import it.
		# If not, then it's either a directory (obsolete) or malformed, so ignore it.
		if (tar tzf "$LATEST_INDEX" >/dev/null 2>&1); then
			mkdir -p "$CORE_DATA/index"
			# remove the index.properties file so default index config is used
			rm -f $CORE_DATA/index.properties
			# wipe old index files if any, and unpack the archived index
			rm -f $CORE_DATA/index/*; tar -xzf "$LATEST_INDEX" -C $CORE_DATA/index
		fi
	EOS
	only_if { ::File.directory? efs_data_dir }
end

# Add DNS entry for service host
#
bash "Add #{service_name} DNS entry" do
	user "root"
	code <<-EOS
		server_id=$(echo "#{node['datashades']['hostname']}" |tr -cd '[[:digit:]]')
		echo "${server_id}" > /etc/#{service_name}id
		sed -i "/#{service_name}_/d" /etc/hostnames
		if [ "${server_id}" -eq 1 ]; then
			failover_type=master
		else
			failover_type=slave
		fi
		alias="#{node['datashades']['app_id']}#{service_name}${server_id}.#{node['datashades']['tld']}"
		echo "#{service_name}_${failover_type}=${alias}" >> /etc/hostnames
	EOS
end

service service_name do
	action [:enable, :start]
end

