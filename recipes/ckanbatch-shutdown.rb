#
# Runs tasks whenever instance leaves or enters the online state or EIP/ELB config changes
#
# Copyright 2021, Queensland Government
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

# Hide this instance from others
#
include_recipe "datashades::stackparams"

file "/data/#{node['datashades']['hostname']}" do
	ignore_failure true # just in case it does not exist
	action :delete
end

bash "Archive remaining logs" do
	user "root"
	cwd "/"
	code <<-EOS
		/etc/cron.daily/logrotate
		/usr/local/bin/archive-logs.sh ckan
	EOS
end
