#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>), William Dutton (<will.dutt@gmail.com>)
# Cookbook Name:: datashades
# Recipe:: swapfile
#
# Sets up a swapfile on the root disk
# Setup another swap on external disk for more speed if it is used during normal operations
# Since extra disk is attached on stage one chef, it is dynamically added on opsworks setup
#
# Ensure root disk is bigger than 8gb else issues will happen down the line, i.e. 100gb per below:
#   OpsWorksInstance:
#    Type: AWS::OpsWorks::Instance
#    Properties:
# ...
#      RootDeviceType: ebs
#      BlockDeviceMappings:
#        - DeviceName: "ROOT_DEVICE"
#          Ebs:
#            DeleteOnTermination: true
#            VolumeSize: 100
#            VolumeType: "gp2"
# ...
#
# Copyright 2022, Queensland Government
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

bash "create swap file #{node['datashades']['swapfile_name']}" do
  user 'root'
  code <<-EOC
    dd if=/dev/zero of=#{node['datashades']['swapfile_name']} bs=1024 count=#{node['datashades']['swapfile_size']}
    mkswap #{node['datashades']['swapfile_name']}
    chown root:root #{node['datashades']['swapfile_name']}
    chmod 0600 #{node['datashades']['swapfile_name']}
  EOC
  creates node['datashades']['swapfile_name']
end

mount 'swap' do
  action :enable
  device node['datashades']['swapfile_name']
  fstype 'swap'
end

bash 'activate all swap devices' do
  user 'root'
  code 'swapon -a'
end

extra_disk = "/mnt/local_data"
if ::File.directory?(extra_disk) then
    swap_file = "#{extra_disk}/swapfile_2g"
    bash "Add swap disk" do
        code <<-EOS
            dd if=/dev/zero of=#{swap_file} bs=1024 count=2M
            chown root:root #{swap_file}
            chmod 0600 #{swap_file}
            mkswap #{swap_file}
        EOS
        not_if { ::File.exist?(swap_file) }
    end

    execute "Enable swap disk" do
        command "swapon -s | grep '^#{swap_file} ' || swapon #{swap_file}"
    end
end
