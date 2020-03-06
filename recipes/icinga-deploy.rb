#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: icinga-deploy
#
# Configures Icinga2 client parameters if Icinga2 master defined
#
# Copyright 2017, Link Digital
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

bash "Deploy Icinga2" do
	user "root"
	code <<-EOS
		client=$(hostname)
		icingamaster="#{node['datashades']['icinga']['master']}"

		mkdir -p /etc/icinga2/pki
		chown -R icinga:icinga /etc/icinga2/pki
		icinga2 pki new-cert --cn ${client} --key /etc/icinga2/pki/${client}.key --cert /etc/icinga2/pki/${client}.crt
		icinga2 pki save-cert --key /etc/icinga2/pki/${client}.key --cert /etc/icinga2/pki/${client}.crt --trustedcert /etc/icinga2/pki/${icingamaster}.crt --host ${icingamaster}

		# create ticket for client so it can register against server
		ticketclient="link-ticket-client"
		ticketpass="#{node['datashades']['icinga']['password']}"
		ticket=$(curl -k -s -u ${ticketclient}:${ticketpass} -H 'Accept: application/json' -X POST "https://${icingamaster}:5665/v1/actions/generate-ticket" -d "{ \"cn\": \"${client}\" }" | jq '.results[].ticket' | tr -d '"')
		echo "Ticket ID: ${ticket}"

		# force fqdn in hosts and setup node
		metadata_token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token)
		pub_ip=$(curl -H "X-aws-ec2-metadata-token: $metadata_token" http://169.254.169.254/latest/meta-data/public-ipv4)
		echo $pub_ip $client >> /etc/hosts
		icinga2 node setup --ticket ${ticket} --endpoint ${icingamaster} --zone ${client} --master_host ${icingamaster} --trustedcert /etc/icinga2/pki/${icingamaster}.crt --accept-commands --accept-config
		sed -i "s/${pub_ip} ${client}//g" /etc/hosts

		echo 'object Zone "global-templates" { global = true }' >> /etc/icinga2/zones.conf

		sed -i 's/include_recursive "conf.d"/\/\/include_recursive "conf.d"/g' /etc/icinga2/icinga2.conf

		chkconfig icinga2 on
		service icinga2 start
	EOS
	not_if { ::File.exist? "/etc/icinga2/pki/#{node['datashades']['icinga']['master']}.crt" }
end

