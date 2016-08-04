#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Attributes:: gfs
#
# Defines attributes required by GlusterFS Service
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

default['datashades']['gfs']['packages'] = ['fuse', 'fuse-libs', 'glusterfs-server', 'glusterfs-fuse', 'nfs-utils', 'nfs-utils-lib']
default['datashades']['gfs']['exports'] = []
default['datashades']['gfs']['cidr'] = '172.31.0.0/16'
default['datashades']['gfs']['maxhosts'] = 2

default['datashades']['gfs-client']['packages'] = ['fuse', 'fuse-libs', 'glusterfs-fuse', 'nfs-utils', 'nfs-utils-lib']
