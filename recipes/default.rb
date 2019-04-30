#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default
#
# Implements base configuration for instances
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

# Set timezone to default value
#
link "/etc/localtime" do
	to "/usr/share/zoneinfo/#{node['datashades']['timezone']}"
	link_type :symbolic
end

# Store timezone config so yum updates don't reset the timezone
#
template '/etc/sysconfig/clock' do
	source 'clock.erb'
	owner 'root'
	group 'root'
	mode '0755'
end

# Enable RedHat EPEL
#
execute "Enable EPEL" do
	command "sed -i 's/enabled=0/enabled=1/g'  /etc/yum.repos.d/epel.repo"
end

# Install/remove core packages
#
node['datashades']['core']['packages'].each do |p|
	package p
end

node['datashades']['core']['unwanted-packages'].each do |p|
	package p do
		action :remove
	end
end

# real basic stuff needs to go in first so jq available for new stack params that uses jq early on
#
include_recipe "datashades::stackparams"

# Install Icinga2 package
#
include_recipe "datashades::icinga-setup"

# Enable yum-cron so updates are downloaded on running nodes
#
service "yum-cron" do
	action [:enable, :start]
end

# Enable nano syntax highlighing
#
cookbook_file '/etc/nanorc' do
  source 'nanorc'
  owner 'root'
  group 'root'
  mode '0755'
end

# Add some helpful stuff to bash
#
cookbook_file "/etc/profile.d/datashades.sh" do
	source "datashades_bash.sh"
	owner 'root'
	group 'root'
	mode '0755'
end

# Make sure all instances have an /etc/zoneid
#
bash "Adding AWS ZoneID" do
	user "root"
	code <<-EOS
	zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
	echo "zoneid=${zoneid}" > /etc/awszoneid
	EOS
end

# Install cli53 for Failover recordset creation
#
remote_file "/sbin/cli53" do
	source "https://github.com/barnybug/cli53/releases/download/0.8.5/cli53-linux-amd64"
	owner 'root'
	mode '0755'
end

# Create DNS helper script
#
cookbook_file "/sbin/checkdns" do
	source "checkdns"
	owner 'root'
	group 'root'
	mode '0755'
end

# Push stats to enable Cloudwatch monitoring
#
cwmon_artifact = "CloudWatchMonitoringScripts-1.2.2.zip"
remote_file "/opt/aws/#{cwmon_artifact}" do
	source "https://aws-cloudwatch.s3.amazonaws.com/downloads/#{cwmon_artifact}"
	mode '0644'
end

execute 'Unzip CloudWatch monitoring scripts' do
	command "unzip -u -q /opt/aws/#{cwmon_artifact} -d /opt/aws/"
end

file "/etc/cron.d/cwpump" do
	content "*/5 * * * * root perl /opt/aws/aws-scripts-mon/mon-put-instance-data.pl --mem-util --mem-used --mem-avail --swap-util --disk-space-util --disk-space-avail --disk-path=/ --auto-scaling --from-cron"
	mode '0644'
end

# Replace default mail relay with Nuxeo AWS SMTP Relay
directory "/usr/share/aws-smtp-relay" do
	action :create
end

cookbook_file "/usr/share/aws-smtp-relay/aws-smtp-relay-1.0.0-jar-with-dependencies.jar" do
	source "aws-smtp-relay-1.0.0-jar-with-dependencies.jar"
end

template "/etc/init.d/aws-smtp-relay" do
	source "aws-smtp-relay.erb"
	mode "0755"
end
