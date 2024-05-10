#
# Installs an OpsWorks app's source via pip, including dependencies.
# datashades_pip_install_app
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
    apprelease = apprelease.dup if apprelease.frozen?

    # Get the version number from the app revision, by preference,
    # or from the app URL if revision is not defined.
    # Either way, ensure that the version number is stripped from the URL.
    if is_git then
        version = new_resource.revision
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
        new_install = false
        if is_git then
            execute "Ensure correct #{new_resource.service_name} Git origin" do
                user new_resource.account_name
                group new_resource.account_name
                cwd install_dir
                command "git remote set-url origin '#{apprelease}'"
            end
        end
    else
        new_install = true
        if is_git then
            apprelease.sub!(/^(https?:)/, 'git+\1')
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

    bash "Install #{version} revision of #{new_resource.service_name}" do
        user new_resource.account_name
        group new_resource.account_name
        cwd install_dir
        code <<-EOS
            if [ "#{is_git}" = "true" ]; then
                # retrieve latest branch metadata
                git fetch --tags -f origin '#{version}' || exit 1
                # make versioned files pristine
                git clean -f
                git reset --hard
                find . -name '*.pyc' -delete
                # check if we actually need to change anything
                if [ "#{new_install}" != "true" ]; then
                    if (git tag -l '#{version}' >/dev/null); then
                        git diff '#{version}' >/dev/null || SKIP_INSTALL=1
                    elif (git branch -l '#{version}' >/dev/null); then
                        git diff 'origin/#{version}' >/dev/null || SKIP_INSTALL=1
                    fi
                fi
                # move to target revision
                git checkout '#{version}' || exit 1
                # get latest changes if we're checking out a branch, otherwise it doesn't matter
                git pull
                # regenerate metadata
                #{new_resource.virtualenv_dir}/bin/python setup.py develop
            fi
            if [ "$SKIP_INSTALL" != "1" ]; then
                PYTHON_MAJOR_VERSION=$(#{new_resource.virtualenv_dir}/bin/python -c "import sys; print(sys.version_info.major)")
                PYTHON_REQUIREMENTS_FILE=requirements-py$PYTHON_MAJOR_VERSION.txt
                if [ -f $PYTHON_REQUIREMENTS_FILE ]; then
                    REQUIREMENTS_FILE=$PYTHON_REQUIREMENTS_FILE
                else
                    CKAN_MINOR_VERSION=$(#{new_resource.virtualenv_dir}/bin/python -c "import ckan; print(ckan.__version__)" | grep -o '^[0-9]*[.][0-9]*')
                    CKAN_REQUIREMENTS_FILE=requirements-$CKAN_MINOR_VERSION.txt
                    if [ -f "$CKAN_REQUIREMENTS_FILE" ]; then
                        REQUIREMENTS_FILE=$CKAN_REQUIREMENTS_FILE
                    else
                        REQUIREMENTS_FILE=requirements.txt
                    fi
                fi
                if [ -f "$REQUIREMENTS_FILE" ]; then
                    REQUIREMENTS_FILES="-r $REQUIREMENTS_FILE"
                fi
                # ckanext-harvest uses this filename
                if [ -f "pip-requirements.txt" ]; then
                    REQUIREMENTS_FILES="$REQUIREMENTS_FILES -r pip-requirements.txt"
                fi
                #{pip} install -e . $REQUIREMENTS_FILES || exit 1
            fi
        EOS
    end
end
