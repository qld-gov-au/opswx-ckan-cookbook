#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default-configure
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

extra_disk = "/mnt/local_data"
if ::File.directory?(extra_disk) then
	swap_file = "#{extra_disk}/swapfile_1g"
	bash "Add swap disk" do
		code <<-EOS
			dd if=/dev/zero of=#{swap_file} bs=1024 count=1M
			mkswap #{swap_file}
			swapon #{swap_file}
		EOS
		not_if { ::File.exist?(swap_file) }
	end

	bash "Enable swap disk on boot" do
		code <<-EOS
			sed -i '\\|^#{swap_file} |d' /etc/fstab
			echo '#{swap_file} swap swap defaults 0 2' >> /etc/fstab
		EOS
	end
end

template "/usr/local/bin/archive-logs.sh" do
	source "archive-logs.sh.erb"
	owner "root"
	group "root"
	mode "0755"
end

# Archive regular system logs to S3.
# This will automatically compress anything at /var/log, but not recursively;
# however, if logs in subdirectories are already compressed by logrotate,
# then they will be archived too.
file "/etc/cron.daily/archive-system-logs-to-s3" do
	content "LOG_DIR=/var/log /usr/local/bin/archive-logs.sh system >/dev/null 2>&1\n"
	owner "root"
	group "root"
	mode "0755"
end

# Run updateDNS script
#
execute 'update dns' do
	command	'/bin/updatedns'
	user 'root'
	group 'root'
	only_if { ::File.exist? "/bin/updatedns" }
end

# Recover from DNS failures
#
cookbook_file "/usr/local/bin/fix-dns.sh" do
	source "fix-dns.sh"
	owner "root"
	group "root"
	mode "0744"
end

file "/etc/cron.d/fix-dns" do
	content "*/5 * * * * root /usr/local/bin/fix-dns.sh\n"
	mode '0644'
end

# Update custom auditd rules
#
template '/etc/audit/rules.d/link.rules' do
	source 'auditd.rules.erb'
	owner 'root'
end

# Remove unwanted cron job from previous script versions
#
file '/etc/cron.daily/manageadmins' do
	action :delete
end

service 'aws-smtp-relay' do
	action [:enable, :restart]
end

# Re-enable and start in case it was stopped by previous recipe versions
service 'sendmail' do
	action [:enable, :start]
end
