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
stack = search("aws_opsworks_stack", "name:#{node['datashades']['version']}_*").first
node.default['datashades']['sitename'] = stack['name']
node.default['datashades']['region'] = stack['region']
vpc_id = stack['vpc_id']

# Get the VPC CIDR for NFS services
#
bash "Get VPC CIDR" do
	user "root"
	code <<-EOS
		placement=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
		region=$(echo ${placement%?})
		aws ec2 describe-vpcs --region ${region} --vpc-ids "#{vpc_id}" | jq '.Vpcs[].CidrBlock' | tr -d '"' > /etc/vpccidr
	EOS
end

# Put the VPC CIDR into a node variable for use in templates
#
ruby_block "Override NFS CIDR attribute" do
	block do
		node.override['datashades']['nfs']['cidr'] = File.read("/etc/vpccidr").delete!("\n")
	end
end

# Get some details about what instance we're running on for recipes
#
instance = search("aws_opsworks_instance", "self:true").first
node.default['datashades']['instid'] = instance['ec2_instance_id']
node.default['datashades']['hostname'] = instance['hostname']

