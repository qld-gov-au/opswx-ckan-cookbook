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
if not batchlayer
	batchlayer = search("aws_opsworks_app", "shortname:ckan-#{node['datashades']['version']}-batch").first
end
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
	'data-qld-theme' => 'data_qld_theme',
	'odi-certificates' => 'odi_certificates',
	'dcat' => 'dcat structured_data',
	'scheming' => 'scheming_datasets',
	'data-qld' => 'data_qld',
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

# Ordering constraints for plugins.
# This affects template overrides.
#
extordering =
{
	'data_qld_theme' => 10,
	'odi_certificates' => 20,
	'dcat structured_data' => 30,
	'data_qld' => 40,
	'scheming_datasets' => 50
}

installed_ordered_exts = Set[]

# Install any packages required by extensions
#
node['datashades']['ckan_ext']['packages'].each do |p|
	package p
end

# Do the actual extension installation using pip
#
search("aws_opsworks_app", 'shortname:*ckanext*').each do |app|

	app['shortname'].sub! '_', '-'
	pluginname = "#{app['shortname']}".sub(/.*ckanext-/, "")

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
		virtualenv_dir = "/usr/lib/ckan/default"
		pip = "#{virtualenv_dir}/bin/pip --cache-dir=/tmp/"
		install_dir = "#{virtualenv_dir}/src/#{app['shortname']}"

		# Many extensions use a different name on the plugins line so these need to be managed
		#
		extname = pluginname
		if extnames.has_key? pluginname
			extname = extnames[pluginname]
		end

		unless (::File.directory?("#{install_dir}"))

			log 'debug' do
	  			message "Installing #{pluginname} #{app['shortname']} from #{apprelease} into #{install_dir}"
				level :info
			end

			# Install the extension and its requirements
			#
			execute "Pip Install #{app['shortname']}" do
				user "ckan"
				group "ckan"
				command "#{pip} install -e '#{apprelease}'"
			end
		end

		apprevision = app['app_source']['revision']
		if ! apprevision
			apprevision = "master"
		end

		execute "Check out selected revision" do
			user "ckan"
			group "ckan"
			cwd "#{install_dir}"
			command "git fetch; git checkout '#{apprevision}'; git pull"
		end

		bash "Install #{app['shortname']} requirements" do
			user "ckan"
			group "ckan"
			cwd "#{install_dir}"
			code <<-EOS
				if [ -f "requirements.txt" ]; then
					#{pip} install -r requirements.txt
				fi
				if [ -f "pip-requirements.txt" ]; then
					#{pip} install -r "pip-requirements.txt"
				fi
			EOS
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
			bash "Enable #{app['shortname']} plugin before #{insert_before}" do
				user "ckan"
				cwd "/etc/ckan/default"
				code <<-EOS
					if [ -z  "$(grep 'ckan.plugins.*#{extname} production.ini')" ]; then
						sed -i "/^ckan.plugins/ s/ #{insert_before} / #{extname} #{insert_before} /" production.ini
					fi
				EOS
			end
		else
			bash "Enable #{app['shortname']} plugin" do
				user "ckan"
				cwd "/etc/ckan/default"
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
			bash "#{app['shortname']} ext config" do
				user "ckan"
				cwd "/etc/ckan/default"
				code <<-EOS
					if [ -z  "$(grep 'ckan.views.default_views.*#{extname}' production.ini)" ]; then
						sed -i "/^ckan.views.default_views/ s/$/ #{viewname}/" production.ini
					fi
				EOS
			end
		end

		# Viewhelpers is a special case because stats needs to be loaded before it
		#
		if "#{pluginname}".eql? 'viewhelpers' then
			bash "View Helpers CKAN ext config" do
				user "ckan"
				cwd "/etc/ckan/default"
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
				user "ckan"
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
	end
end

# Enable DataStore and DataPusher extensions if desired
# No installation necessary in CKAN 2.2+
bash "Enable DataStore-related extensions" do
	user "ckan"
	cwd "/etc/ckan/default"
	code <<-EOS
		if [ -z  "$(grep 'ckan.plugins.*datastore' production.ini)" ]; then
			sed -i "/^ckan.plugins/ s/$/ datastore/" production.ini
		fi
		if [ -z  "$(grep 'ckan.plugins.*datapusher' production.ini)" ]; then
			sed -i "/^ckan.plugins/ s/$/ datapusher/" production.ini
		fi
	EOS
	only_if { "yes".eql? node['datashades']['ckan_web']['dsenable']}
end
