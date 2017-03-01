#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Attributes:: ckan
#
# Defines attributes required by CKAN recipes
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

default['datashades']['ckan_web']['endpoint'] = '/'
default['datashades']['ckan_web']['packages'] = ['xml-commons', 'git', 'postgresql94-devel', 'postgresql94', 'python27-devel', 'python27-pip', 'libxslt', 'libxslt-devel', 'libxml2', 'libxml2-devel', 'gcc', 'gcc-c++', 'make', 'java-1.7.0-openjdk-devel', 'java-1.6.0-openjdk', 'xalan-j2', 'unzip', 'policycoreutils-python', 'mod24_wsgi-python27']

default['datashades']['ckan_web']['dbuser'] = 'ckan_default'
default['datashades']['ckan_web']['dbname'] = 'ckan_default'
default['datashades']['ckan_web']['dsuser'] = 'ckan_datastore'
default['datashades']['ckan_web']['dsname'] = 'ckan_datastore'

default['datashades']['ckan_web']['adminpw'] = 'adminpw'
default['datashades']['ckan_web']['adminemail'] = 'admin@nowhere.com'

default['datashades']['ckan_web']['sentryurl'] = ''

default['datashades']['ckan_web']['disqus'] = 'ckan'

default['datashades']['ckan_ext']['packages'] = ['geos-devel.x86_64', 'npm']

default['datashades']['postgres']['password'] = ""

# Postgres settings
default['datashades']['ckan_db']['packages'] = ['postgresql94-server', 'postgresql94', 'postgresql94-devel', 'libtool', 'libxml2-devel', 'geos-devel']
default['datashades']['ckan_db']['version'] = '94'
