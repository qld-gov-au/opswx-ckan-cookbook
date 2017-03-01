#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Attributes:: nginx
#
# Defines attributes required by NGINX web service
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

default['datashades']['nginx']['packages'] = ['nfs-utils', 'nfs-utils-lib', 'nginx', 'perl', 'libaio', 'git', 'telnet', 'ghostscript', 'ImageMagick', 'php55', 'php55-fpm', 'php55-opcache', 'php55-pecl-apcu', 'php55-pdo', 'php55-mysqlnd', 'php55-pecl-memcache', 'php55-pecl-memcached', 'php55-mbstring', 'php55-gd', 'php55-mcrypt', 'php55-soap', 'mysql']
default['datashades']['nginx']['ssl'] = false
default['datashades']['nginx']['maxdl'] = '512M'
default['datashades']['nginx']['mem_limit'] = '256M'
default['datashades']['nginx']['default_server'] = ''
default['datashades']['nginx']['locations'] = ''
default['datashades']['app']['locations'] = ''
