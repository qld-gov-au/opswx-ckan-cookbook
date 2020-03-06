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

service_name = 'solr'

file "/data/solr-healthcheck_#{node['datashades']['hostname']}" do
	action :delete
end

# Remove DNS records to stop requests to this host
#
bash "Delete #{service_name} DNS record" do
	user "root"
	code <<-EOS
		zone_id=$(cat /etc/awszoneid | grep zoneid | cut -d'=' -f 2)
		metadata_token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
		instance_hostname=$(curl -H "X-aws-ec2-metadata-token: $metadata_token" http://169.254.169.254/latest/meta-data/hostname)
		dns_name=$(grep "#{service_name}_" /etc/hostnames | cut -d'=' -f 2)
		route53 del_record ${zone_id} ${dns_name} CNAME ${instance_hostname} 60
	EOS
end

service "#{service_name}" do
	action [:stop]
end

bash "Archive remaining logs" do
	user "solr"
	cwd "/"
	code <<-EOS
		TIMESTAMP=`date +'%s'`
		for logfile in `ls -d /var/log/solr/*log`; do
			mv "$logfile" "$logfile.$TIMESTAMP"
			gzip "$logfile.$TIMESTAMP"
		done
		/usr/local/bin/archive-logs.sh solr
	EOS
end
