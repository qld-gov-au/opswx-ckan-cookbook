#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: nfs-setup
#
# Creates NFS server role with data drive stored on separate EBS volume
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

service_name = 'nfs'

# Install necessary packages
#
node['datashades'][service_name]['packages'].each do |p|
  package p
end

# Add DNS entry for service host
#
bash "Add #{service_name} DNS entry" do
  user "root"
  code <<-EOS
    echo "#{service_name}_name=#{node['datashades']['version']}#{service_name}.#{node['datashades']['tld']}" >> /etc/hostnames
  EOS
  not_if "grep -q '#{service_name}_name' /etc/hostnames"
end

# Create script to update DNS on configure events
#
cookbook_file '/bin/updatedns' do
  source 'updatedns'
  owner 'root'
  group 'root'
  mode '0755'
end

# Run updateDNS script
#
execute "Update #{node['datashades']['hostname']} #{service_name} DNS" do
  command	'/bin/updatedns'
  user 'root'
  group 'root'
end

# Create data volume daily backup cron job
#
template '/etc/cron.daily/datavol_backup' do
  source 'ebs_backup.erb'
  owner 'root'
  group 'root'
  mode '0755'
end

# Create data volume monthly backup cron job
#
cookbook_file '/etc/cron.monthly/datavol_backup' do
  source 'monthly_backup'
  owner 'root'
  group 'root'
  mode '0755'
end

# Tag the Data volume so it's easily identified
#
bash "Tagging Data Volume Instance" do
  user 'root'
  group 'root'
  code <<-EOS
  volume=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="#{node['datashades']['instid']}" Name=attachment.delete-on-termination,Values=false --region "#{node['datashades']['region']}")
  vol_id=$(echo ${volume} | jq '.Volumes[].VolumeId' | tr -d '"')
  aws ec2 create-tags --resources "${vol_id}" --tags Key=Name,Value="#{node['datashades']['hostname']}-data" Key=Version,Value="#{node['datashades']['version'].upcase}" --region "#{node['datashades']['region']}"
  EOS
end
