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
	'data-qld' => 'data_qld data_qld_integration data_qld_google_analytics',
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
	'validation' => 20,
	'data-qld data_qld_integration data_qld_google_analytics' => 25,
	'scheming_datasets' => 30,
	'resource_type_validation' => 33,
	'validation-schema-generator' => 36,
	'dcat structured_data' => 40,
	'qa' => 43,
	'archiver' => 46,
	'report' => 49,
	'harvester_data_qld_geoscience' => 50,
	'harvest' => 53,
	'qgovext' => 56,
	'ytp_comments' =>59,
	'datarequests' => 60,
	'csrf_filter' => 63,
	'ssm_config' => 93
	'odi_certificates' => 94,
	'resource-visibility' => 95
}


installed_ordered_exts = Set[]

# Install any packages required by extensions
#
node['datashades']['ckan_ext']['packages'].each do |p|
	package p
end

bash "Install NPM and NodeJS" do
	code <<-EOS
		if ! (yum install -y npm); then
			# failed to install from standard repo, try a manual setup
			curl --silent --location https://rpm.nodesource.com/setup_10.x | bash -
			yum -y install nodejs
		fi
	EOS
end

# Do the actual extension installation using pip
#
harvester_data_qld_geoscience_present = false
archiver_present = false
resource_visibility_present = false
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

	execute "#{pluginname}: Validation CKAN ext database init" do
		user "#{account_name}"
		command "PASTER_PLUGIN=ckanext-validation #{ckan_cli} validation init-db || echo 'Ignoring expected error, see https://github.com/frictionlessdata/ckanext-validation/issues/44'"
		only_if { "#{pluginname}".eql? 'validation' }
	end

	bash "#{pluginname}: YTP CKAN ext database init" do
		user "#{account_name}"
		code <<-EOS
			export PASTER_PLUGIN=ckanext-ytp-comments
			#{ckan_cli} comments initdb || echo 'Ignoring expected error'
			#{ckan_cli} comments init_notifications_db || echo 'Ignoring expected error'
			#{ckan_cli} comments updatedb || echo 'Ignoring expected error'
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

			cookbook_file "/etc/supervisord.d/supervisor-ckan-harvest.ini" do
				source "supervisor-ckan-harvest.conf"
				mode "0744"
			end

			# only have one server trigger harvest initiation, which then worker queues harvester fetch/gather works through the queues.
			file "/etc/cron.hourly/ckan-harvest-run" do
				content "/usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-harvest #{ckan_cli} harvester run >> /var/log/ckan/ckan-harvest-run.log 2>&1\n"
				mode "0755"
			end
		end
	end

    if "#{pluginname}".eql? 'harvester-data-qld-geoscience'
        harvester_data_qld_geoscience_present = true
        #Add ckanext.harvester_data_qld_geoscience:geoscience_dataset.json to scheming.dataset_schemas
        bash "Inject geoscience_dataset if missing" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z "$(grep 'ckanext.harvester_data_qld_geoscience:geoscience_dataset.json' production.ini)" ]; then
					# scheming.dataset_schemas = ckanext.data_qld:ckan_dataset.json ckanext.harvester_data_qld_geoscience:geoscience_dataset.json
					sed -i "s/ckanext.data_qld:ckan_dataset.json/ckanext.data_qld:ckan_dataset.json ckanext.harvester_data_qld_geoscience:geoscience_dataset.json/g" production.ini;
				fi
			EOS
		end
    end

    if "#{pluginname}".eql? 'resource-visibility'
        bash "Inject resource-visibility scheming preset if missing" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z "$(grep 'ckanext.resource_visibility:schema/presets.json' production.ini)" ]; then
					# scheming.presets = ckanext.scheming:presets.json ckanext.data_qld:presets.json ckanext.resource_visibility:schema/presets.json
					sed -i "s|ckanext.data_qld:presets.json|ckanext.data_qld:presets.json ckanext.resource_visibility:schema/presets.json|g" production.ini;
				fi
			EOS
		end
		if batchnode
			resource_visibility_present = true
			# Run dataset require updates notifications at 7am and 7:15am on batch
			file "/etc/cron.d/ckan-dataset-resource-visibility-notify-privacy-assessments" do
				content "00 7 * * MON-FRI root /usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=resource_visibility #{ckan_cli} resource_visibility notify_privacy_assessments >> /var/log/ckan/ckan-dataset-resource-visibility-notify-privacy-assessments.log 2>&1\n"
				mode '0644'
				owner "root"
				group "root"
			end
		end
	end

	if "#{pluginname}".eql? 'data-qld'
		if batchnode
        	# Run dataset require updates notifications at 7am and 7:15am on batch
            file "/etc/cron.d/ckan-dataset-notification-due" do
                content "00 7 * * MON root /usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-data-qld #{ckan_cli} send_email_dataset_due_to_publishing_notification >> /var/log/ckan/ckan-dataset-notification-due.log 2>&1\n"\
                        "15 7 * * MON root /usr/local/bin/pick-job-server.sh && PASTER_PLUGIN=ckanext-data-qld #{ckan_cli} send_email_dataset_overdue_notification >> /var/log/ckan/ckan-dataset-notification-overdue.log 2>&1\n"
                mode '0644'
                owner "root"
                group "root"
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

			cookbook_file "/etc/supervisord.d/supervisor-ckan-archiver.ini" do
				source "supervisor-ckan-archiver.conf"
				mode "0744"
			end

			template "/usr/local/bin/archiverTriggerAll.sh" do
				source 'archiverTriggerAll.sh'
				owner 'root'
				group 'root'
				mode '0755'
			end

			#Trigger at 6:30am twice a month
			file "/etc/cron.d/ckan-archiverTriggerAll" do
				content "30 6 1,15 * * ckan /usr/local/bin/pick-job-server.sh && /usr/local/bin/archiverTriggerAll.sh  >> /var/log/ckan/ckan-archiverTriggerAll.log 2>&1\n"
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
			command "sed -i 's|^\\(use\s*=\\)\\(.*:FriendlyFormPlugin\\)|#\\1\\2\\n\\1 ckanext.csrf_filter.token_protected_friendlyform:TokenProtectedFriendlyFormPlugin|g' #{config_dir}/who.ini"
		end
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
			command <<-'SED'.strip + " #{virtualenv_dir}/lib/*/site-packages/messytables/types.py"
				sed -i "s/^\(\s*\)return parser[.]parse(value)/\1try:\n\1    return parser.isoparse(value)\n\1except ValueError:\n\1    return parser.parse(value, dayfirst=True)/"
			SED
		end
	end
end

if not archiver_present then
	execute "Clean Archiver supervisor config" do
		command "find /etc/supervisor* -name 'supervisor-ckan-archiver*' -delete"
	end

	execute "Clean Archiver cron" do
		command "rm -f /etc/cron.*/ckan-archiver*"
	end
end

if not resource_visibility_present then
   execute "Clean Resource Visibility cron" do
        command "rm -f /etc/cron.d/ckan-dataset-resource-visibility-notify-privacy-assessments*"
   end
end

if not harvest_present then
	execute "Clean Harvest supervisor config" do
		command "find /etc/supervisor* -name 'supervisor-ckan-harvest*' -delete"
	end

	execute "Clean Harvest cron" do
		command "rm -f /etc/cron.*/ckan-harvest*"
	end
end
# if extra items are added for harvester_data_qld_geoscience then use this to remove on disable (i.e. cron jobs etc)
# if not harvester_data_qld_geoscience_present then
# 	#clean production.ini of ckanext.harvester_data_qld_geoscience:geoscience_dataset.json
#     bash "Remove geoscience_dataset if set" do
#         user "#{account_name}"
#         cwd "#{config_dir}"
#         code <<-EOS
#             if [ -n "$(grep 'ckanext.harvester_data_qld_geoscience:geoscience_dataset.json' production.ini)" ]; then
#                 sed -i "s/ ckanext.harvester_data_qld_geoscience:geoscience_dataset.json//g" production.ini;
#             fi
#         EOS
#     end
# end

if not csrf_present then
	bash "revert CSRF plugin from Repoze config" do
		user "#{account_name}"
		code <<-EOS
			sed -i 's/^\\(use\\s*=ckanext[.]csrf_filter[.]token_protected_friendlyform:TokenProtectedFriendlyFormPlugin\\)/#\\1/g' #{config_dir}/who.ini
			sed -i 's/^#\\(use\\s*=.*:FriendlyFormPlugin\\)/\\1/g' #{config_dir}/who.ini"
		EOS
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

# #pyOpenSSL 22.0.0 (2022-01-29) - dropped py2 support but has issues on py3 which stops harvester working
# #pyOpenSSL 23.0.0 (2023-01-01) - required due to harvest:  Error: HTTP general exception: module 'lib' has no attribute 'SSL_CTX_set_ecdh_auto'
bash "Min pyOpenSSL for python3" do
    user "#{account_name}"
    code <<-EOS
            #{pip} install pyOpenSSL>=23.0.0
    EOS
end