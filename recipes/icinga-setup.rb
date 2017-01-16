#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: icinga-setup
#
# Installs binaries for icinga2 from EPEL repo
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

include_recipe "datashades::stackparams"

bash "Install Icinga2" do
	user "root"
	code <<-EOS
		yum install -y https://packages.icinga.org/epel/6/release/noarch/icinga-rpm-release-6-1.el6.noarch.rpm
		sed -i 's/$releasever/6/g' /etc/yum.repos.d/ICINGA-*.repo
		yum install -y icinga2 nagios-plugins-all
	EOS
	not_if { ::File.directory? "/etc/icinga2" }
end