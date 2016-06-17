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

stack = search("aws_opsworks_stack", "name:#{node['datashades']['version']}_*").first
node.default['datashades']['sitename'] = stack['name']
node.default['datashades']['region'] = stack['region']

instance = search("aws_opsworks_instance", "self:true").first
node.default['datashades']['instid'] = instance['ec2_instance_id']
node.default['datashades']['hostname'] = instance['hostname']

