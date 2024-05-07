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
require 'date'

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
	'xloader' => 85,
	'datastore' => 80
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
resource_visibility_present = false
harvest_present = false
csrf_present = false

plugin_names = {}
plugin_urls = []
node['datashades']['ckan_web']['plugin_app_names'].each do |plugin|

	egg_name = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/shortname" --query "Parameter.Value" --output text`.strip
	type = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/type" --query "Parameter.Value" --output text`.strip
	revision = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/revision" --query "Parameter.Value" --output text`.strip
	url = `aws ssm get-parameter --region "#{node['datashades']['region']}" --name "/config/CKAN/#{node['datashades']['version']}/app/#{node['datashades']['app_id']}/plugin_apps/#{plugin}/app_source/url" --query "Parameter.Value" --output text`.strip.sub(/@(.*)/, '')
	plugin_urls.push("#{type}+#{url}@#{revision}#egg=#{egg_name}")

	# Install Extension
	#

	# Many extensions use a different name on the plugins line so these need to be managed
	#
	pluginname = egg_name.sub(/.*ckanext-/, "")
	extname = pluginname.gsub '-', '_'
	if extnames.has_key? pluginname
		extname = extnames[pluginname]
	end
	plugin_names[plugin] = extname

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
end

plugin_url_string = plugin_urls.join("' '")

log "#{DateTime.now}: Installing plugin eggs"
execute "Install plugins" do
	user account_name
	group account_name
	command "#{pip} install -e '#{plugin_url_string}'"
end

log "#{DateTime.now}: Installing plugin requirement files"
bash "Install plugin requirements" do
	cwd "#{virtualenv_dir}/src"
	code <<-EOS
		PYTHON_MAJOR_VERSION=$(#{python} -c "import sys; print(sys.version_info.major)")
		PYTHON_REQUIREMENTS_FILE=requirements-py$PYTHON_MAJOR_VERSION.txt
		CKAN_MINOR_VERSION=$(#{python} -c "import ckan; print(ckan.__version__)" | grep -o '^[0-9]*[.][0-9]*')
		CKAN_REQUIREMENTS_FILE=requirements-$CKAN_MINOR_VERSION.txt
		for extension in `ls -d ckanext-*`; do
			if [ -f $extension/$PYTHON_REQUIREMENTS_FILE ]; then
				REQUIREMENTS_FILES="$REQUIREMENTS_FILES -r $PYTHON_REQUIREMENTS_FILE"
			else
				if [ -f "$extension/$CKAN_REQUIREMENTS_FILE" ]; then
					REQUIREMENTS_FILES="$REQUIREMENTS_FILES -r $CKAN_REQUIREMENTS_FILE"
				else
					REQUIREMENTS_FILES="$REQUIREMENTS_FILES -r requirements.txt"
				fi
			fi
			# ckanext-harvest uses this filename
			if [ -f "$extension/pip-requirements.txt" ]; then
				REQUIREMENTS_FILES="$REQUIREMENTS_FILES -r pip-requirements.txt"
			fi
		done
		#{pip} install $REQUIREMENTS_FILES
	EOS
end

sorted_plugin_names = plugin_names.values.sort_by { |a, b|
	if extordering.key? a then
		if extordering.key? b then
			return extordering[a] - extordering[b]
		else
			# ordered plugins come before unordered
			return -1
		end
	else
		if extordering.key? b then
			return 1
		else
			return a.to_i - b.to_i
		end
	end
}
plugins_config = "stats resource_proxy text_view webpage_view recline_grid_view image_view audio_view video_view recline_view recline_graph_view recline_map_view datatables_view #{sorted_plugin_names}"

execute "Enable plugins" do
	user "#{account_name}"
	cwd "#{config_dir}"
	command "sed -i 's/^ckan[.]plugins.*/ckan.plugins = #{plugins_config}/' #{config_file}"
end

node['datashades']['ckan_web']['plugin_app_names'].each do |plugin|

	pluginname = plugin_names[plugin]

	log "#{DateTime.now}: Running custom actions for plugin #{pluginname}"
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
#             if [ -n "$(grep 'ckanext.harvester_data_qld_geoscience:geoscience_dataset.json' #{config_file})" ]; then
#                 sed -i "s/ ckanext.harvester_data_qld_geoscience:geoscience_dataset.json//g" #{config_file};
#             fi
#         EOS
#     end
# end

if not csrf_present then
	bash "revert CSRF plugin from Repoze config" do
		user "#{account_name}"
		code <<-EOS
			sed -i 's/^\\(use\\s*=ckanext[.]csrf_filter[.]token_protected_friendlyform:TokenProtectedFriendlyFormPlugin\\)/#\\1/g' #{config_dir}/who.ini
			sed -i 's/^#\\(use\\s*=.*:FriendlyFormPlugin\\)/\\1/g' "#{config_dir}/who.ini"
		EOS
	end
end

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
