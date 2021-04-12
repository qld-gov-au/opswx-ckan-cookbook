#
# Installs an OpsWorks app's source via pip, including dependencies.
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

# Installed name, eg 'ckan'
property :service_name, String, name_property: true
# Operating system account name to install as
property :account_name, String, default: 'ckan'
# App type, eg 'git'
property :type, String
# App revision if version-controlled, eg 'main'
property :revision, String, default: 'master'
# App source URL
property :url, String
# Virtualenv to install to
property :virtualenv_dir, String, default: '/usr/lib/ckan/default'

action :create do
    pip = "#{new_resource.virtualenv_dir}/bin/pip --cache-dir=/tmp/"
    install_dir = "#{new_resource.virtualenv_dir}/src/#{new_resource.service_name}"
    is_git = new_resource.type.casecmp("git") == 0

    apprelease = new_resource.url

    # Get the version number from the app revision, by preference,
    # or from the app URL if revision is not defined.
    # Either way, ensure that the version number is stripped from the URL.
    if is_git then
        version = new_resource.revision
        apprelease.sub!('http', "git+http")
        apprelease.sub!("#{new_resource.service_name}/archive/", "#{new_resource.service_name}.git@")
        apprelease.sub!('.zip', "")
    end
    if apprelease.include? "@" then
        urlrevision = apprelease[/@(.*)/].sub '@', ''
        apprelease.sub!(/@(.*)/, '')
    end
    version ||= urlrevision
    version ||= "master"

    #
    # Install selected revision
    #

    if (::File.exist? "#{install_dir}/setup.py") then
        if is_git then
            execute "Ensure correct #{new_resource.service_name} Git origin" do
                user new_resource.account_name
                group new_resource.account_name
                cwd install_dir
                command "git remote set-url origin '#{apprelease}'"
            end
        end
    else
        if is_git then
            apprelease << "@#{version}"
        end
        if ! apprelease.include? '#egg' then
            apprelease << "#egg=#{new_resource.service_name}"
        end
        execute "Install #{new_resource.service_name} #{version}" do
            user new_resource.account_name
            group new_resource.account_name
            command "#{pip} install -e '#{apprelease}'"
        end
    end

    bash "Check out #{version} revision of #{new_resource.service_name}" do
        user new_resource.account_name
        group new_resource.account_name
        cwd install_dir
        code <<-EOS
            # retrieve latest branch metadata
            git fetch origin '#{version}'
            # drop unversioned files
            git clean
            # make versioned files pristine
            git reset --hard
            git checkout '#{version}'
            # get latest changes if we're checking out a branch, otherwise it doesn't matter
            git pull
            # drop compiled files from previous branch
            find . -name '*.pyc' -delete
            # regenerate metadata
            #{new_resource.virtualenv_dir}/bin/python setup.py develop
        EOS
        only_if { is_git }
    end

    bash "Install Python dependencies for #{new_resource.service_name}" do
        user new_resource.account_name
        group new_resource.account_name
        cwd install_dir
        code <<-EOS
            PYTHON_MAJOR_VERSION=$(python -c "import sys; print(sys.version_info.major)")
            PY2_REQUIREMENTS_FILE=requirements-py2.txt
            if [ "$PYTHON_MAJOR_VERSION" = "2" ] && [ -f $PY2_REQUIREMENTS_FILE ]; then
                REQUIREMENTS_FILE=$PY2_REQUIREMENTS_FILE
            else
                REQUIREMENTS_FILE=requirements.txt
            fi
            if [ -f "$REQUIREMENTS_FILE" ]; then
                #{pip} install -r $REQUIREMENTS_FILE
            fi
            # ckanext-harvest uses this filename
            if [ -f "pip-requirements.txt" ]; then
                #{pip} install -r "pip-requirements.txt"
            fi
        EOS
    end
end
