#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Attributes:: nfs
#
# Defines attributes required by NFS Service
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
#

default['datashades']['nfs']['packages'] = ['nfs-utils', 'nfs-utils-lib']
default['datashades']['nfs']['exports'] = ["/data/nfs/shared_content", "/data/nfs/logs/#{node['datashades']['sitename']}_nginx", "/data/nfs/logs/#{node['datashades']['sitename']}_apache"]
default['datashades']['nfs']['cidr'] = '172.31.0.0/16'
default['datashades']['nfs']['paths'] = ['/data/nfs/' => false, '/data/nfs/logs' => false]
