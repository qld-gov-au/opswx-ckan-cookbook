#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: ckanparams
#
# Defines some default parameters for CKAN deployments.
#
# Copyright 2024, Queensland Government
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

include_recipe "datashades::stackparams"

# Retrieve attributes from SSM Parameter Store
node.default['datashades']['ckan_web']['google']['analytics_id'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/common/GaId" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['google']['gtm_container_id'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/common/GtmId" --query "Parameter.Value" --output text`.strip
node.default['datashades']['attachments_bucket'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/s3AttachmentBucket" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['public_tld'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/public_tld" --query "Parameter.Value" --output text`.strip
node.default['datashades']['tld'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/tld" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['title'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/title" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['site_domain'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/site_domain" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['dsenable'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/ds_enable" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['adminemail'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/admin_email" --query "Parameter.Value" --output text`.strip
node.default['datashades']['ckan_web']['adminpw'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/admin_password" --query "Parameter.Value" --with-decryption --output text`.strip
node.default['datashades']['ckan_web']['beaker_secret'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/beaker_secret" --query "Parameter.Value" --with-decryption --output text`.strip
node.default['datashades']['ckan_web']['dbuser'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/db/#{node['datashades']['app_id']}_user" --query "Parameter.Value" --output text`.strip
node.default['datashades']['postgres']['password'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/db/#{node['datashades']['app_id']}_password" --query "Parameter.Value" --with-decryption --output text`.strip

node.default['datashades']['ckan_web']['plugin_app_names'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_app_names" --query "Parameter.Value" --output text`.strip.split(',')
for plugin in node['datashades']['ckan_web']['plugin_app_names'] do
    node.default['datashades']['ckan_web']['plugin_apps'][plugin]['name'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/name" --query "Parameter.Value" --output text`.strip
    node.default['datashades']['ckan_web']['plugin_apps'][plugin]['shortname'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/shortname" --query "Parameter.Value" --output text`.strip
    node.default['datashades']['ckan_web']['plugin_apps'][plugin]['app_source']['type'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/type" --query "Parameter.Value" --output text`.strip
    node.default['datashades']['ckan_web']['plugin_apps'][plugin]['app_source']['url'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/url" --query "Parameter.Value" --output text`.strip
    node.default['datashades']['ckan_web']['plugin_apps'][plugin]['app_source']['revision'] = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/revision" --query "Parameter.Value" --output text`.strip
end

# Derive defaults from other values
node.default['datashades']['sitename'] = "#{node['datashades']['ckan_web']['dbname']}_#{node['datashades']['version']}"
node.default['datashades']['ckan_web']['dsname'] = "#{node['datashades']['ckan_web']['dbname']}_datastore"
node.default['datashades']['ckan_web']['dsuser'] = "#{node['datashades']['ckan_web']['dbuser']}_datastore"
node.default['datashades']['ckan_web']['email_domain'] = node['datashades']['ckan_web']['public_tld']
