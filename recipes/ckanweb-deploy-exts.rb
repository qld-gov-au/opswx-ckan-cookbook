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

# Batch nodes only need a limited set of extensions for harvesting
# Ascertain whether or not the instance deploying is a batch node
#
require 'json'

batchnode = node['datashades']['layer'] == 'batch'

account_name = "ckan"
virtualenv_dir = "/usr/lib/ckan/default"
python = "#{virtualenv_dir}/bin/python"
pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
ckan_cli = "#{virtualenv_dir}/bin/ckan_cli"
config_dir = "/etc/ckan/default"
config_file = "production.ini"

# Hash to map extname to pluginname
#
extnames =
{
	'qgov' => 'qgovext',
	'dcat' => 'dcat structured_data',
	'scheming' => 'scheming_datasets',
	'data-qld' => 'data_qld data_qld_google_analytics',
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
# Keys must match what will actually be injected into the config, so:
# - Plugins that appear in the 'extnames' hash must use the value of
#   that hash, eg 'scheming_datasets' instead of just 'scheming'.
# - Hyphens should be replaced with underscores.
#
extordering =
{
	'data_qld data_qld_google_analytics' => 1,
	'dcat structured_data' => 5,
	'validation' => 10,
	'resource_type_validation' => 20,
	'validation_schema_generator' => 21,
	'qgovext' => 25,
	'report' => 30,
	'datarequests' => 31,
	'ytp_comments' =>35,
	'csrf_filter' => 40,
	'scheming_datasets' => 45,
	'qa' => 50,
	'archiver' => 51,
	'harvest ckan_harvester' => 52,
	'harvester_data_qld_geoscience' => 53,
	'odi_certificates' => 60,
	'resource_visibility' => 70,
	'ssm_config' => 80,
	'datastore' => 80,
	'xloader' => 85,
	'clamav' => 90,
	's3filestore' => 95
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
			# TODO stop ignoring broken packages
			# once we're away from OpsWorks and on a recent AMI
			yum -y install nodejs --skip-broken
		fi
	EOS
end

# Do the actual extension installation using pip
#
harvester_data_qld_geoscience_present = false
archiver_present = false
report_present = false
resource_visibility_present = false
harvest_present = false

# Ensure plugins that depend on others are installed last
dependent_plugins = ['CKANExtArchiver', 'CKANExtQa', 'CKANExtHarvestDataQldGeoScience']
sorted_plugin_names = []
dependent_plugin_names = []
node['datashades']['ckan_web']['plugin_app_names'].each do |plugin|
	if dependent_plugins.include? plugin then
		dependent_plugin_names.append(plugin)
	else
		sorted_plugin_names.append(plugin)
	end
end

# Ensure Archiver comes before QA
dependent_plugin_names.sort!

sorted_plugin_names.concat(dependent_plugin_names)
sorted_plugin_names.each do |plugin|

	retries = 0
	egg_name = nil
	source_type = 'git'
	source_revision = nil
	source_url = nil
	5.times do
		plugin_parameters = `aws ssm get-parameters-by-path --region "#{node['datashades']['region']}" --recursive --path "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}" --query "Parameters[].{Name: Name, Value: Value}"`.strip
		if not (plugin_parameters.nil? or plugin_parameters == '') then
			JSON.parse(plugin_parameters).each do |parameter|
				if parameter['Name'].end_with?('/shortname') then
					egg_name = parameter['Value']
				elsif parameter['Name'].end_with?('/app_source/type') then
					source_type = parameter['Value']
				elsif parameter['Name'].end_with?('/app_source/revision') then
					source_revision = parameter['Value']
				elsif parameter['Name'].end_with?('/app_source/url') then
					source_url = parameter['Value']
				end
			end
			break
		end
	end

	# Install Extension
	#

	datashades_pip_install_app egg_name do
		type source_type
		revision source_revision
		url source_url
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
				if [ -z  "$(grep 'ckan.plugins.*#{extname} #{config_file}')" ]; then
					sed -i "/^ckan.plugins/ s/ #{insert_before} / #{extname} #{insert_before} /" #{config_file}
				fi
			EOS
		end
	else
		bash "Enable #{egg_name} plugin" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z  "$(grep 'ckan.plugins.*#{extname} #{config_file}')" ]; then
					sed -i "/^ckan.plugins/ s/$/ #{extname} /" #{config_file}
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
				if [ -z  "$(grep 'ckan.views.default_views.*#{extname}' #{config_file})" ]; then
					sed -i "/^ckan.views.default_views/ s/$/ #{viewname}/" #{config_file}
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

			if system('yum info supervisor')
				cookbook_file "/etc/supervisord.d/supervisor-ckan-harvest.ini" do
					source "supervisor-ckan-harvest.conf"
					mode "0744"
				end
			else
				# Create files with our preferred ownership to work around https://github.com/systemd/systemd/issues/14385
				execute "Start Harvester log files" do
					user account_name
					group account_name
					command "touch /var/log/ckan/ckan-harvest-fetch.log /var/log/ckan/ckan-harvest-gather.log"
				end
				systemd_unit "ckan-worker-harvest-fetch.service" do
					content({
						Unit: {
							Description: 'CKAN Harvest Fetch worker',
							After: 'network-online.target'
						},
						Service: {
							User: account_name,
							ExecStart: '/usr/lib/ckan/default/bin/ckan_cli harvester fetch_consumer',
							Restart: 'on-failure',
							StandardOutput: 'append:/var/log/ckan/ckan-harvest-fetch.log',
							StandardError: 'append:/var/log/ckan/ckan-harvest-fetch.log'
						},
						Install: {
							WantedBy: 'multi-user.target'
						}
					})
					action [:create, :enable]
				end
				systemd_unit "ckan-worker-harvest-gather.service" do
					content({
						Unit: {
							Description: 'CKAN Harvest Gather worker',
							After: 'network-online.target'
						},
						Service: {
							User: account_name,
							ExecStart: '/usr/lib/ckan/default/bin/ckan_cli harvester gather_consumer',
							Restart: 'on-failure',
							StandardOutput: 'append:/var/log/ckan/ckan-harvest-gather.log',
							StandardError: 'append:/var/log/ckan/ckan-harvest-gather.log'
						},
						Install: {
							WantedBy: 'multi-user.target'
						}
					})
					action [:create, :enable]
				end
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
				if [ -z "$(grep 'ckanext.harvester_data_qld_geoscience:geoscience_dataset.json' #{config_file})" ]; then
					# scheming.dataset_schemas = ckanext.data_qld:ckan_dataset.json ckanext.harvester_data_qld_geoscience:geoscience_dataset.json
					sed -i "s/ckanext.data_qld:ckan_dataset.json/ckanext.data_qld:ckan_dataset.json ckanext.harvester_data_qld_geoscience:geoscience_dataset.json/g" #{config_file};
				fi
			EOS
		end
    end

	if "#{pluginname}".eql? 'resource-visibility'
		bash "Inject resource-visibility scheming preset if missing" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ -z "$(grep 'ckanext.resource_visibility:schema/presets.json' #{config_file})" ]; then
					# scheming.presets = ckanext.scheming:presets.json ckanext.data_qld:presets.json ckanext.resource_visibility:schema/presets.json
					sed -i "s|ckanext.data_qld:presets.json|ckanext.data_qld:presets.json ckanext.resource_visibility:schema/presets.json|g" #{config_file};
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

	if "#{pluginname}".eql? 'clamav'
		if not batchnode
			package 'clamav'
			package 'clamd'

			bash "Enable Clam daemons" do
				code <<-EOS
					freshclam
					systemctl enable clamav-freshclam
					systemctl enable clamd@scan
				EOS
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

			if system('yum info supervisor')
				cookbook_file "/etc/supervisord.d/supervisor-ckan-archiver.ini" do
					source "supervisor-ckan-archiver.conf"
					mode "0744"
				end
			else
				# Create files with our preferred ownership to work around https://github.com/systemd/systemd/issues/14385
				execute "Start Archiver log files" do
					user account_name
					group account_name
					command "touch /var/log/ckan/ckan-worker-bulk.log /var/log/ckan/ckan-worker-priority.log"
				end
				systemd_unit "ckan-worker-bulk.service" do
					content({
						Unit: {
							Description: 'CKAN low-priority job worker',
							After: 'network-online.target'
						},
						Service: {
							User: account_name,
							ExecStart: '/usr/lib/ckan/default/bin/ckan_cli jobs worker bulk',
							Restart: 'on-failure',
							StandardOutput: 'append:/var/log/ckan/ckan-worker-bulk.log',
							StandardError: 'append:/var/log/ckan/ckan-worker-bulk.log'
						},
						Install: {
							WantedBy: 'multi-user.target'
						}
					})
					action [:create, :enable]
				end
				systemd_unit "ckan-worker-priority.service" do
					content({
						Unit: {
							Description: 'CKAN high-priority job worker',
							After: 'network-online.target'
						},
						Service: {
							User: account_name,
							ExecStart: '/usr/lib/ckan/default/bin/ckan_cli jobs worker priority',
							Restart: 'on-failure',
							StandardOutput: 'append:/var/log/ckan/ckan-worker-priority.log',
							StandardError: 'append:/var/log/ckan/ckan-worker-priority.log'
						},
						Install: {
							WantedBy: 'multi-user.target'
						}
					})
					action [:create, :enable]
				end
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

		if batchnode
			report_present = true

			file "/etc/cron.daily/refresh_reports" do
				content "/usr/local/bin/pick-job-server.sh && #{ckan_cli} report generate >> /var/log/ckan/ckan-report-run.log\n"
				mode '0755'
				owner "root"
				group "root"
			end
		end
	end

	if "#{pluginname}".eql? 'datarequests'
		bash "Data Requests database init" do
			user "#{account_name}"
			code <<-EOS
				# initialise database tables if this version has CLI support
				if (#{ckan_cli} datarequests --help); then
					#{ckan_cli} datarequests init-db
					#{ckan_cli} datarequests update-db
				fi
			EOS
		end
	end

	# Viewhelpers is a special case because stats needs to be loaded before it
	#
	if "#{pluginname}".eql? 'viewhelpers' then
		bash "View Helpers CKAN ext config" do
			user "#{account_name}"
			cwd "#{config_dir}"
			code <<-EOS
				if [ ! -z "$(grep 'viewhelpers' #{config_file})" ] && [ -z "$(grep 'stats viewhelpers' #{config_file})" ]; then
					sed -i "s/viewhelpers/ /g" #{config_file};
					sed -i "s/stats/stats viewhelpers/g" #{config_file};
				fi
			EOS
		end
	end

	# Install any additional pip packages required
	#
	if extextras.has_key? pluginname
		pip_packages = extextras[pluginname]
		execute "Install extra PIP packages for #{pluginname}" do
			user "#{account_name}"
			command "#{pip} install #{pip_packages}"
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
end

if not archiver_present then
	if system('yum info supervisor')
		execute "Clean Archiver supervisor config" do
			command "find /etc/supervisor* -name 'supervisor-ckan-archiver*' -delete"
		end
	else
		systemd_unit "ckan-worker-bulk.service" do
			action [:stop, :delete]
		end
		systemd_unit "ckan-worker-priority.service" do
			action [:stop, :delete]
		end
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

if not report_present then
	execute "Clean Report cron" do
		command "rm -f /etc/cron.daily/refresh_reports*"
	end
end

if not harvest_present then
	if system('yum info supervisor')
		execute "Clean Harvest supervisor config" do
			command "find /etc/supervisor* -name 'supervisor-ckan-harvest*' -delete"
		end
	else
		systemd_unit "ckan-worker-harvest-fetch.service" do
			action [:stop, :delete]
		end
		systemd_unit "ckan-worker-harvest-gather.service" do
			action [:stop, :delete]
		end
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
#             if [ -n "$(grep 'ckanext.harvester_data_qld_geoscience:geoscience_dataset.json' #{config_file})" ]; then
#                 sed -i "s/ ckanext.harvester_data_qld_geoscience:geoscience_dataset.json//g" #{config_file};
#             fi
#         EOS
#     end
# end

# Enable DataStore extension if desired
if ["yes", "y", "true", "t"].include? node['datashades']['ckan_web']['dsenable'].downcase then
	bash "Enable DataStore-related extensions" do
		user "ckan"
		cwd "#{config_dir}"
		code <<-EOS
			if [ -z  "$(grep 'ckan.plugins.*datastore' #{config_file})" ]; then
				sed -i "/^ckan.plugins/ s/$/ datastore/" #{config_file}
			fi
		EOS
	end

	cookbook_file "#{config_dir}/allowed_functions.txt" do
		source 'allowed_functions.txt'
		owner "#{account_name}"
		group "#{account_name}"
		mode "0755"
	end
end

bash "Enable Activity Streams extension on CKAN 2.10+" do
	user "#{account_name}"
	cwd "#{config_dir}"
	code <<-EOS
		if [ -d "#{virtualenv_dir}/src/ckan/ckanext/activity" ]; then
			sed -i "/^ckan.plugins/ s/$/ activity /" #{config_file}
		fi
	EOS
end

# 'click' version 7.1.2 does not match goodtables' claimed requirements,
# but it does work in practice.
bash "Pin 'click' version to make Goodtables and Frictionless coexist" do
	user "#{account_name}"
	code <<-EOS
		if (#{pip} show click |grep 'Version: [1-6][.]') then
			#{pip} install 'click==7.1.2' 'typer<0.12'
		fi
	EOS
end
