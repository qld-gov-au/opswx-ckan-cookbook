#
# Creates web server for CKAN
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


include_recipe "datashades::default"
include_recipe "datashades::ckan-setup"
include_recipe "datashades::nginx-setup"

virtualenv_dir = "/usr/lib/ckan/default"

# uWSGI is available from the yum repositories,
# but it's an old and buggy version, so use pip.
execute "Install uWSGI" do
    user 'ckan'
    command "#{virtualenv_dir}/bin/pip install uwsgi --cache-dir=/tmp/"
end
