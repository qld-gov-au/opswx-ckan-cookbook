#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: zookeeper-shutdown
#
# Runs tasks whenever instance is shutdown
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

bash "Delete Zookeepr DNS record" do
	user "root"
	code <<-EOS
	zone_id=$(cat /etc/awszoneid | grep zoneid | cut -d'=' -f 2)
	pub_host=$(wget -q -O - http://169.254.169.254/latest/meta-data/public-hostname)
	dns_name=$(grep 'zk_name' /etc/hostnames | cut -d'=' -f 2)
	route53 del_record ${zone_id} ${dns_name} CNAME ${pub_host} 60
	EOS
end