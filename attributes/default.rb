#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Attributes:: default
#
# Defines default attributes required by Datashades OpsWorks Stack
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

# default['datashades']['timezone'] = 'Australia/Brisbane' using Queensland due to pythong 2 not having Brisbane
default['datashades']['timezone'] = 'Australia/Queensland'
default['datashades']['sitename'] = 'ckan'

default['datashades']['backup']['retention'] = '30'

default['datashades']['core']['packages'] = ['yum-cron', 'clamav', 'gcc', 'jq', 'java-1.8.0-openjdk', 'perl-Switch', 'perl-DateTime', 'perl-Sys-Syslog', 'perl-LWP-Protocol-https', 'perl-Digest-SHA.x86_64', 'git', 'telnet']
default['datashades']['core']['unwanted-packages'] = ['java-1.7.0-openjdk']

default['datashades']['jumpbox']['usergroup'] = ''
default['datashades']['jumpbox']['bucket'] = ''

default['datashades']['log_bucket'] = 'osssio-ckan-web-logs'

default['datashades']['auditd']['rules'] = []

include_attribute "datashades::ckan"
include_attribute "datashades::nfs"
include_attribute "datashades::nginx"
include_attribute "datashades::solr"
include_attribute "datashades::icinga"

