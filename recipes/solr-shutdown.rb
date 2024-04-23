#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: solr-shutdown
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

include_recipe "datashades::stackparams"

service_name = 'solr'

file "/data/solr-healthcheck_#{node['datashades']['hostname']}" do
	ignore_failure true # just in case it does not exist
	action :delete
end

# Remove DNS records to stop requests to this host
#
bash "Delete #{service_name} DNS record" do
	ignore_failure true # just in case it does not exist
	user "root"
	code <<-EOS
		zone_id=$(cat /etc/awszoneid | grep zoneid | cut -d'=' -f 2)
		metadata_token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
		instance_hostname=$(curl -H "X-aws-ec2-metadata-token: $metadata_token" http://169.254.169.254/latest/meta-data/hostname)
		dns_name=$(grep "#{service_name}_" /etc/hostnames | cut -d'=' -f 2)
		aws route53 change-resource-record-sets --hosted-zone-id ${zone_id} --change-batch file://<(cat <<-EOF
			{"Changes": [
				{"Action": "DELETE", "ResourceRecordSet": {
					"Name": "${dns_name}", "Type": "CNAME", "TTL": 60,
					"ResourceRecords": [{"Value": "$instance_hostname"}]
				}}
			]}
		EOF
		)
	EOS
end
