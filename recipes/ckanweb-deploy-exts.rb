#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: ckanweb-deploy-exts
#
# Deploys CKAN Extensions to web layer
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

instance = search("aws_opsworks_instance", "self:true").first

# Batch nodes only need a limited set of extensions for harvesting
# Ascertain whether or not the instance deploying is a batch node
#
batchlayer = search("aws_opsworks_layer", "shortname:#{node['datashades']['app_id']}-#{node['datashades']['version']}-batch").first
batchnode = false
unless batchlayer.nil?
	batchnode = instance['layer_ids'].include?(batchlayer['layer_id'])
end
batchexts = ['datastore', 'datapusher', 'harvest', 'datajson', 'spatial']

# Hash to map extname to pluginname
#
extnames =
{
	'qgov' => 'qgovext',
	'officedocs' => 'officedocs_view',
	'cesiumpreview' => 'cesium_viewer',
	'basiccharts' => 'linechart barchart piechart basicgrid',
	'scheming' => 'scheming_datasets',
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

# Install any packages required by extensions
#
node['datashades']['ckan_ext']['packages'].each do |p|
	package p
end

# Do the actual extension installation using pip
#
search("aws_opsworks_app", 'shortname:*ckanext*').each do |app|

	app['shortname'].sub! '_', '-'
	pluginname = "#{app['shortname']}".sub! 'ckanext-', ""

	# Don't install extensions not required by the batch node
	#
	installext = !batchnode || (batchnode && batchexts.include?(pluginname))
	unless (!installext)
		apprelease = app['app_source']['url']
		apprelease.sub! 'http', "git+http"

		if ! apprelease.include? '#egg' then
			apprelease << "#egg=#{app['shortname']}"
		end

		# Install Extension
		#
		unless (::File.directory?("/usr/lib/ckan/default/src/#{app['shortname']}"))

			log 'debug' do
	  			message "Installing #{pluginname} #{app['shortname']} from #{apprelease} into /usr/lib/ckan/default/src/#{app['shortname']}"
				level :info
			end

			# Many extensions use a different name on the plugins line so these need to be managed
			#
			extname = pluginname
			if extnames.has_key? pluginname
				extname = extnames[pluginname]
			end

			# Install the extension and add its name to production.ini
			#
			bash "Pip Install #{app['shortname']}" do
				user "root"
				cwd "/usr/lib/ckan/default/src"
				code <<-EOS
					/usr/lib/ckan/default/bin/pip install -e "#{apprelease}"
					if [ -z  "$(cat /etc/ckan/default/production.ini | grep 'ckan.plugins.*#{extname}')" ]; then
						sed -i "/^ckan.plugins/ s/$/ #{extname}/" /etc/ckan/default/production.ini
					fi
					if [ -f "/usr/lib/ckan/default/src/#{app['shortname']}/requirements.txt" ]; then
					    /usr/lib/ckan/default/bin/pip install -r "/usr/lib/ckan/default/src/#{app['shortname']}/requirements.txt"
					fi
					if [ -f "/usr/lib/ckan/default/src/#{app['shortname']}/pip-requirements.txt" ]; then
					    /usr/lib/ckan/default/bin/pip install -r "/usr/lib/ckan/default/src/#{app['shortname']}/pip-requirements.txt"
					fi
				EOS
			end

			# Add the extension to the default_views line if required
			#
			if extviews.has_key? pluginname
				viewname = extviews[pluginname]
				bash "#{app['shortname']} ext config" do
					user "root"
					code <<-EOS
						if [ -z  "$(cat /etc/ckan/default/production.ini | grep 'ckan.views.default_views' | grep '#{extname}')" ]; then
							sed -i "/^ckan.views.default_views/ s/$/ #{viewname}/" /etc/ckan/default/production.ini
						fi
					EOS
					not_if "grep 'ckan.views.default_views' | grep '#{extname}' /etc/ckan/default/production.ini"
				end
			end

			# Viewhelpers is a special case because stats needs to be loaded before it
			#
			if "#{pluginname}".eql? 'viewhelpers' then
				bash "View Helpers CKAN ext config" do
					user "root"
					code <<-EOS
						if [ ! -z "$(cat /etc/ckan/default/production.ini | grep 'viewhelpers')" ] && [ -z "$(cat /etc/ckan/default/production.ini | grep 'stats viewhelpers')" ]; then
							sed -i "s/viewhelpers/ /g" /etc/ckan/default/production.ini;
							sed -i "s/stats/stats viewhelpers/g" /etc/ckan/default/production.ini;
						fi
					EOS
				end
			end

			# Install any additional pip packages required
			#
			if extextras.has_key? pluginname
				pip_packages = extextras[pluginname]
				bash "Install extra PIP packages for #{pluginname}" do
					user "root"
					code <<-EOS
						read -r -a packages <<< "#{pip_packages}"
						for package in "${packages[@]}"
						do
							pip install ${package}
						done
					EOS
				end
			end

			# Cesium preview requires some NPM extras
			#
			if "#{pluginname}".eql? 'cesiumpreview' then
				bash "Cesium Preview CKAN ext config" do
					user "root"
					code <<-EOS
						npm install --save geojson-extent
					EOS
					not_if { ::File.directory?("/usr/lib/node_modules/geojson-extent") }
				end
			end

		end
	end
end

# Enable DataStore and DataPusher extensions if desired
# No installation necessary in CKAN 2.2+
bash "Enable DataStore-related extensions" do
	user "root"
	cwd "/etc/ckan/default"
	code <<-EOS
		if [ -z  "$(grep 'ckan.plugins.*\bdatastore\b' production.ini)" ]; then
			sed -i "/^ckan.plugins/ s/$/ datastore/" production.ini
		fi
		if [ -z  "$(grep 'ckan.plugins.*\bdatapusher\b' production.ini)" ]; then
			sed -i "/^ckan.plugins/ s/$/ datapusher/" production.ini
		fi
	EOS
	only_if { "yes".eql? node['datashades']['ckan_web']['dsenable'] }
end
