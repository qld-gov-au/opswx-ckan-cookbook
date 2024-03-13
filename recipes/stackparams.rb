#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: stackparams
#
# Defines some default paramaters from AWS OpsWorks Stack being provisioned.
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

# Obtain some stack attributes for the recipes to use
#

# Retrieve attributes from instance metadata
metadata_token=`curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token`
node.default['datashades']['region'] = `curl -H "X-aws-ec2-metadata-token: #{metadata_token}" http:/169.254.169.254/latest/meta-data/placement/region`
node.default['datashades']['instid'] = `curl -H "X-aws-ec2-metadata-token: #{metadata_token}" http:/169.254.169.254/latest/meta-data/instance-id`

# Retrieve attributes from instance tags
node.default['datashades']['version'] = `aws ec2 describe-tags --region #{node['datashades']['region']} --filters "Name=resource-id,Values=#{node['datashades']['instid']}" 'Name=key,Values=Environment' --query 'Tags[].Value' --output text`.strip
node.default['datashades']['layer'] = `aws ec2 describe-tags --region #{node['datashades']['region']} --filters "Name=resource-id,Values=#{node['datashades']['instid']}" 'Name=key,Values=Layer' --query 'Tags[].Value' --output text`.strip
node.default['datashades']['hostname'] = `aws ec2 describe-tags --region #{node['datashades']['region']} --filters "Name=resource-id,Values=#{node['datashades']['instid']}" 'Name=key,Values=opsworks:instance' --query 'Tags[].Value' --output text`.strip
node.default['datashades']['ckan_web']['dbname'] = `aws ec2 describe-tags --region #{node['datashades']['region']} --filters "Name=resource-id,Values=#{node['datashades']['instid']}" 'Name=key,Values=Service' --query 'Tags[].Value' --output text`.strip

# Retrieve attributes from SSM Parameter Store
node.default['datashades']['log_bucket'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/common/s3LogsBucket" --query "Parameter.Value" --output text`.strip
node.default['datashades']['redis']['hostname'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/common/cache_address" --query "Parameter.Value" --output text`.strip

# Get the VPC CIDR for NFS services
#
bash "Get VPC CIDR" do
	user "root"
	code <<-EOS
		mac_id = `curl -H "X-aws-ec2-metadata-token: #{metadata_token}" http:/169.254.169.254/latest/meta-data/network/interfaces/macs`
		vpc_id = `curl -H "X-aws-ec2-metadata-token: #{metadata_token}" http:/169.254.169.254/latest/meta-data/network/interfaces/macs/$mac_id/vpc-id`
		aws ec2 describe-vpcs --region "#{node['datashades']['region']}" --vpc-ids "$vpc_id" | jq '.Vpcs[].CidrBlock' | tr -d '"' > /etc/vpccidr
	EOS
end

# Put the VPC CIDR into a node variable for use in templates
#
ruby_block "Override NFS CIDR attribute" do
	block do
		node.override['datashades']['nfs']['cidr'] = File.read("/etc/vpccidr").delete!("\n")
	end
end
