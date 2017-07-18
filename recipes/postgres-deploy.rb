#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: postgres-deploy
#
# Deploy Postgres service to Postgres layer
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

unless (::File.directory?("/data/pgsql#{node['datashades']['postgres']['version']}"))	
	pgserv = "postgresql" + node['datashades']['postgres']['version']
	pgdir = "pgsql" + node['datashades']['postgres']['version'] 

	bash 'install_postgres' do
		code <<-EOS
			service "#{pgserv}" initdb
			mv /var/lib/"#{pgdir}" /data/
			ln -sf /data/"#{pgdir}" /var/lib/"#{pgdir}"
			echo "listen_addresses = '*'" >> /data/"#{pgdir}"/data/postgresql.conf
		EOS
	end

	template "/data/#{pgdir}/data/pg_hba.conf" do
	  source 'pg_hba.conf.erb'
	end

	service "#{pgserv}" do
		action [:start, :enable]	
	end
end
