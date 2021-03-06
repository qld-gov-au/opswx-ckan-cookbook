#
# Author:: Carl Antuar (<carl.antuar@smartservice.qld.gov.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-deploy-exts
#
# Deploys CKAN Extensions to web layer
#
# Copyright 2019, Queensland Government
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

instance = search("aws_opsworks_instance", "self:true").first

# Batch nodes only need a limited set of extensions for harvesting
# Ascertain whether or not the instance deploying is a batch node
#
batchlayer = search("aws_opsworks_layer", "shortname:#{node['datashades']['app_id']}-batch").first
if not batchlayer
	batchlayer = search("aws_opsworks_app", "shortname:ckan-#{node['datashades']['version']}-batch").first
end
batchnode = false
unless batchlayer.nil?
	batchnode = instance['layer_ids'].include?(batchlayer['layer_id'])
end

account_name = "ckan"
virtualenv_dir = "/usr/lib/ckan/default"
python = "#{virtualenv_dir}/bin/python"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"
config_dir = "/etc/ckan/default"

# Hash to map extname to pluginname
#
extnames =
{
	'qgov' => 'qgovext',
	'dcat' => 'dcat structured_data',
	'scheming' => 'scheming_datasets',
	'data-qld' => 'data_qld_resources data_qld_integration data_qld_google_analytics data_qld_reporting',
	'publications-qld' => 'data_qld_resources',
	'officedocs' => 'officedocs_view',
	'cesiumpreview' => 'cesium_viewer',
	'basiccharts' => 'linechart barchart piechart basicgrid',
	'pdfview' => 'pdf_view',
	'dashboard' => 'dashboard_preview',
	'datajson' => 'datajson datajson_harvest',
	'harvest' => 'harvest ckan_harvester',
	'spatial' => 'spatial_metadata spatial_query',
	'zippreview' => 'zip_view'
}

# Hash to add plugin to default_views line
#
extviews =
{
	'officedocs' => 'officedocs_view',
	'cesiumpreview' => 'cesium_viewer',
	'pdfview' => 'pdf_view',
	'zippreview' => 'zip_view'
}

# Hash to install extra pip packages
#
extextras =
{
	'datajson' => 'jsonschema',
	'harvest' => 'jsonschema pika',
	'spatial' => 'geoalchemy2 lxml'
}

# Ordering constraints for plugins.
# This affects template overrides.
#
extordering =
{
	'data_qld_theme' => 10,
	'odi_certificates' => 20,
	'dcat structured_data' => 30,
	'data_qld data_qld_google_analytics' => 40,
	'scheming_datasets' => 50,
	'qa' => 60,
	'archiver' => 70,
	'report' => 80
}

installed_ordered_exts = Set[]

# Install any packages required by extensions
#
node['datashades']['ckan_ext']['packages'].each do |p|
	package p
end

# Do the actual extension installation using pip
#
archiver_present = false
harvest_present = false
csrf_present = false
search("aws_opsworks_app", 'shortname:*ckanext*').each do |app|

	egg_name = app['shortname']

	# Install Extension
	#

	datashades_pip_install_app egg_name do
		type app['app_source']['type']
		revision app['app_source']['revision']
		url app['app_source']['url']
	end

	# Many extensions use a different name on the plugins line so these need to be managed
	#
	pluginname = egg_name.sub(/.*ckanext-/, "")
	extname = pluginname.gsub '-', '_'
	if extnames.has_key? pluginname
		extname = extnames[pluginname]
	end

	# Add the extension to production.ini
	# Go as close to the end as possible while respecting the ordering constraints if any
	insert_before = nil
	if extordering.has_key? extname
		min_ordering = extordering[extname]
		max_ordering = 9999
		installed_ordered_exts.each do |prefix|
			installed_ordering = extordering[prefix]
			if installed_ordering > min_ordering and installed_ordering < max_ordering
				insert_before = prefix
				max_ordering = installed_ordering
			end
		end
		installed_ordered_exts.add extname
	end

	if insert_before
		bash "Enable #{egg_name} plugin before #{insert_before}" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z  "$(grep 'ckan.plugins.*#{extname} production.ini')" ]; then
					sed -i "/^ckan.plugins/ s/ #{insert_before} / #{extname} #{insert_before} /" production.ini
				fi
			EOS
		end
	else
		bash "Enable #{egg_name} plugin" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z  "$(grep 'ckan.plugins.*#{extname} production.ini')" ]; then
					sed -i "/^ckan.plugins/ s/$/ #{extname} /" production.ini
				fi
			EOS
		end
	end

	# Add the extension to the default_views line if required
	#
	if extviews.has_key? pluginname
		viewname = extviews[pluginname]
		bash "#{egg_name} view config" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z  "$(grep 'ckan.views.default_views.*#{extname}' production.ini)" ]; then
					sed -i "/^ckan.views.default_views/ s/$/ #{viewname}/" production.ini
				fi
			EOS
		end
	end

	execute "Validation CKAN ext database init" do
		user "#{account_name}"
		command "PASTER_PLUGIN=ckanext-validation #{ckan_cli} validation init-db || echo 'Ignoring expected error, see https://github.com/frictionlessdata/ckanext-validation/issues/44'"
		only_if { "#{pluginname}".eql? 'validation' }
	end

	bash "YTP CKAN ext database init" do
		user "#{account_name}"
		code <<-EOS
			export PASTER_PLUGIN=ckanext-ytp-comments
			#{ckan_cli} initdb || echo 'Ignoring expected error'
			#{ckan_cli} init_notifications_db || echo 'Ignoring expected error'
			#{ckan_cli} updatedb || echo 'Ignoring expected error'
		EOS
		only_if { "#{pluginname}".eql? 'ytp-comments' }
	end

	if "#{pluginname}".eql? 'harvest'
		execute "Harvest CKAN ext database init" do
			user "#{account_name}"
			command "PASTER_PLUGIN=ckanext-harvest #{ckan_cli} harvester initdb || echo 'Ignoring expected error'"
		end

		if batchnode
			harvest_present = true

			cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-harvest.conf" do
				source "supervisor-ckan-harvest.conf"
				mode "0744"
			end

			# only have one server trigger harvest initiation, which then worker queues harvester fetch/gather works through the queues.
			file "/etc/cron.hourly/ckan-harvest-run" do
				content "/usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-harvest #{ckan_cli} harvester run > /dev/null 2>&1\n"
				mode "0755"
			end
		end
	end

	if "#{pluginname}".eql? 'archiver'
		execute "Archiver CKAN ext database init" do
			user "#{account_name}"
			command "PASTER_PLUGIN=ckanext-archiver #{ckan_cli} archiver init || echo 'Ignoring expected error'"
		end

		if batchnode
			archiver_present = true

			cookbook_file "/etc/supervisor/conf.d/supervisor-ckan-archiver.conf" do
				source "supervisor-ckan-archiver.conf"
				mode "0744"
			end

			template "/usr/local/bin/archiverTriggerAll.sh" do
				source 'archiverTriggerAll.sh'
				owner 'root'
				group 'root'
				mode '0755'
			end

			#Trigger at 10pm monday nights weekly
			file "/etc/cron.d/ckan-worker" do
				content "0 22 * * 1 ckan /usr/local/bin/pick-job-server.sh && /usr/local/bin/archiverTriggerAll.sh >/dev/null 2>&1\n"
				mode '0644'
			end
		end
	end

	if "#{pluginname}".eql? 'qa'
		execute "qa CKAN ext database init" do
			user "#{account_name}"
			command "PASTER_PLUGIN=ckanext-qa #{ckan_cli} qa init || echo 'Ignoring expected error'"
		end
	end

	if "#{pluginname}".eql? 'report'
		execute "report CKAN ext database init" do
			user "#{account_name}"
			command "PASTER_PLUGIN=ckanext-report #{ckan_cli} report initdb || echo 'Ignoring expected error'"
		end
	end

	if "#{pluginname}".eql? 'csrf-filter'
		csrf_present = true
		execute "set CSRF plugin in Repoze config" do
			user "#{account_name}"
			command "sed -i 's/repoze[.]who[.]plugins[.]friendlyform:FriendlyFormPlugin/ckanext.csrf_filter.token_protected_friendlyform:TokenProtectedFriendlyFormPlugin/g' #{config_dir}/who.ini"
		end
	end

	bash "Provide custom Bootstrap version" do
		user "#{account_name}"
		group "#{account_name}"
		cwd "#{virtualenv_dir}/src/ckan/ckan/public/base/vendor/bootstrap/js/"
		code <<-EOS
			BOOTSTRAP_VERSION_PATTERN="\\bv[0-9]+\\.[0-9]\\.[0-9]\\b"
			CORE_BOOTSTRAP_VERSION=$(grep -Eo "$BOOTSTRAP_VERSION_PATTERN" bootstrap.min.js)
			CUSTOM_BOOTSTRAP=#{virtualenv_dir}/src/ckanext-data-qld-theme/ckanext/data_qld_theme/bootstrap/
			CUSTOM_BOOTSTRAP_VERSION=$(grep -Eo "$BOOTSTRAP_VERSION_PATTERN" $CUSTOM_BOOTSTRAP/bootstrap.min.js)
			if [ "$CUSTOM_BOOTSTRAP_VERSION" != "" ]; then
				cp $CUSTOM_BOOTSTRAP/bootstrap.js bootstrap-$CUSTOM_BOOTSTRAP_VERSION.js
				cp $CUSTOM_BOOTSTRAP/bootstrap.min.js bootstrap-$CUSTOM_BOOTSTRAP_VERSION.min.js
				if [ -L bootstrap.js ]; then
					rm bootstrap.js bootstrap.min.js
				else
					mv bootstrap.js bootstrap-$CORE_BOOTSTRAP_VERSION.js
					mv bootstrap.min.js bootstrap-$CORE_BOOTSTRAP_VERSION.min.js
				fi
				ln -sf bootstrap-$CUSTOM_BOOTSTRAP_VERSION.js bootstrap.js
				ln -sf bootstrap-$CUSTOM_BOOTSTRAP_VERSION.min.js bootstrap.min.js
			fi
		EOS
		only_if { "#{pluginname}".eql? 'data-qld-theme' }
	end

	# Viewhelpers is a special case because stats needs to be loaded before it
	#
	if "#{pluginname}".eql? 'viewhelpers' then
		bash "View Helpers CKAN ext config" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ ! -z "$(grep 'viewhelpers' production.ini)" ] && [ -z "$(grep 'stats viewhelpers' production.ini)" ]; then
					sed -i "s/viewhelpers/ /g" production.ini;
					sed -i "s/stats/stats viewhelpers/g" production.ini;
				fi
			EOS
		end
	end

	# Install any additional pip packages required
	#
	if extextras.has_key? pluginname
		pip_packages = extextras[pluginname]
		bash "Install extra PIP packages for #{pluginname}" do
			user "#{account_name}"
			code <<-EOS
				read -r -a packages <<< "#{pip_packages}"
				for package in "${packages[@]}"
				do
					#{pip} install ${package}
				done
			EOS
		end
	end

	# Cesium preview requires some NPM extras
	#
	if "#{pluginname}".eql? 'cesiumpreview' then
		execute "Cesium Preview CKAN ext config" do
			user "root"
			command "npm install --save geojson-extent"
		end
	end

	# Work around https://github.com/numpy/numpy/issues/14012
	if "#{pluginname}".eql? 'xloader' then
		execute "Lock numpy version until issue 14012 is fixed" do
			user "#{account_name}"
			command "#{pip} install numpy==1.15.4"
		end

		# The dateparser library defaults to month-first but is configurable.
		# Unfortunately, simply toggling the day-first flag breaks ISO dates.
		# See https://github.com/dateutil/dateutil/issues/402
		execute "Patch date parser format" do
			user "#{account_name}"
			command <<-'SED'.strip + " #{virtualenv_dir}/lib/python2.7/site-packages/messytables/types.py"
				sed -i "s/^\(\s*\)return parser[.]parse(value)/\1for fmt in ['%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%d %H:%M:%S%z', '%Y-%m-%dT%H:%M:%S.%f%z', '%Y-%m-%d %H:%M:%S.%f%z']:\n\1    try:\n\1        return datetime.datetime.strptime(value, fmt)\n\1    except ValueError:\n\1        pass\n\1return parser.parse(value, dayfirst=True)/"
			SED
		end
	end
end

if not archiver_present then
	execute "Clean Archiver supervisor config" do
		command "rm -f /etc/supervisor/conf.d/supervisor-ckan-archiver*.conf"
	end

	execute "Clean Archiver cron" do
		command "rm -f /etc/cron.*/ckan-archiver*"
	end
end

if not harvest_present then
	execute "Clean Harvest supervisor config" do
		command "rm -f /etc/supervisor/conf.d/supervisor-ckan-harvest*.conf"
	end

	execute "Clean Harvest cron" do
		command "rm -f /etc/cron.*/ckan-harvest*"
	end
end

if not csrf_present then
	execute "revert CSRF plugin from Repoze config" do
		user "#{account_name}"
		command "sed -i 's/ckanext[.]csrf_filter[.]token_protected_friendlyform:TokenProtectedFriendlyFormPlugin/repoze.who.plugins.friendlyform:FriendlyFormPlugin/g' #{config_dir}/who.ini"
	end
end

# Enable DataStore and DataPusher extensions if desired
# No installation necessary in CKAN 2.2+
if "yes".eql? node['datashades']['ckan_web']['dsenable'] then
	bash "Enable DataStore-related extensions" do
		user "ckan"
		cwd "#{config_dir}"
		code <<-EOS
			if [ -z  "$(grep 'ckan.plugins.*datastore' production.ini)" ]; then
				sed -i "/^ckan.plugins/ s/$/ datastore/" production.ini
			fi
		EOS
	end

	cookbook_file "#{config_dir}/allowed_functions.txt" do
		source 'allowed_functions.txt'
		owner "#{account_name}"
		group "#{account_name}"
		mode "0755"
	end

	# There is a race condition when uploading a resource; the page tries
	# to display it, while the DataPusher tries to delete and recreate it.
	# Thus, the resource may not exist when the page loads.
	# See https://github.com/ckan/ckan/issues/3980
	execute "Patch upload race condition" do
		user "#{account_name}"
		command <<-'SED'.strip + " #{virtualenv_dir}/src/ckan/ckan/lib/helpers.py"
			sed -i "s/^\(\s\{4\}\)\(result = logic.get_action('datastore_search')({}, data)\)/\1import ckan.plugins as p\n\1try:\n\1\1\2\n\1except p.toolkit.ObjectNotFound:\n\1\1return []/"
		SED
	end
end
