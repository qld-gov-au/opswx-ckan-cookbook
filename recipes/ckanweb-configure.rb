#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-configure
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

# Fix Amazon PYTHON_INSTALL_LAYOUT so items are installed in sites/packages not distr/packages
#
bash "Fix Python Install Layout" do
	user 'root'
	code <<-EOS
	sed -i 's~setenv PYTHON_INSTALL_LAYOUT "amzn"~# setenv PYTHON_INSTALL_LAYOUT "amzn"~g' /etc/profile.d/python-install-layout.csh
	sed -i 's~export PYTHON_INSTALL_LAYOUT="amzn"~# export PYTHON_INSTALL_LAYOUT="amzn"~g' /etc/profile.d/python-install-layout.sh
	unset PYTHON_INSTALL_LAYOUT
	EOS
	not_if "grep '# export PYTHON_INSTALL_LAYOUT' /etc/profile.d/python-install-layout.sh"
end

paster = "/usr/lib/ckan/default/bin/paster --plugin=ckan"
config_file = "/etc/ckan/default/production.ini"

file "/etc/cron.daily/ckan-tracking-update" do
	content "#{paster} tracking update -c #{config_file}\n"
	owner "root"
	group "root"
	mode "0755"
end

file "/etc/cron.hourly/ckan-email-notifications" do
	content "echo '{}' | #{paster} post -c #{config_file} /api/action/send_email_notifications > /dev/null\n"
	owner "root"
	group "root"
	mode "0755"
end

# Update the CKAN site_url with the best public domain name we can find.
# Best is a public DNS alias pointing to CloudFront.
# Next best is the CloudFront distribution domain.
# Use the load balancer address if there's no CloudFront.
#
app = search("aws_opsworks_app", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}*").first
if not app
	app = search("aws_opsworks_app", "shortname:ckan-#{node['datashades']['version']}*").first
end
app_url = app['domains'][0]
bash "Detect public domain name" do
	user "ckan"
	code <<-EOS
		cloudfront_domain=$(aws cloudfront list-distributions --query "DistributionList.Items[].{DomainName: DomainName, OriginDomainName: Origins.Items[0].DomainName}[?contains(OriginDomainName, '#{app_url}')] | [0].DomainName" --output json | tr -d '"')
		if [ "$cloudfront_domain" != "null" ]; then
			public_name="$cloudfront_domain"
			zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['public_tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
			record_name=$(aws route53 list-resource-record-sets --hosted-zone-id $zoneid --query "ResourceRecordSets[].{Name: Name, Target: ResourceRecords[0].Value}[?contains(Target, '$cloudfront_domain')] | [0].Name" --output json |tr -d '"' |sed 's/[.]$//')
			if [ "$record_name" != "null" ]; then
				public_name="$record_name"
				sed -i "s|^smtp[.]mail_from\s*=\([^@]*\)@.*$|smtp.mail_from=\1@$public_name|" /etc/ckan/default/production.ini
			fi
		fi
		if [ ! -z "$public_name" ]; then
			sed -i "s|^ckan[.]site_url\s*=.*$|ckan.site_url=https://$public_name/|" /etc/ckan/default/production.ini
		fi
	EOS
end
