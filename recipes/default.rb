#
# Author:: Shane Davis (<shane.davis@linkdigital.com.au>)
# Cookbook Name:: datashades
# Recipe:: default
#
# Implements base configuration for instances
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

# Add a larger swapfile if we have spare disk space
#
include_recipe "datashades::swapfile"

# Set timezone to default value
#
link "/etc/localtime" do
    to "/usr/share/zoneinfo/#{node['datashades']['timezone']}"
    link_type :symbolic
end

# Store timezone config so yum updates don't reset the timezone
#
template '/etc/sysconfig/clock' do
    source 'clock.erb'
    owner 'root'
    group 'root'
    mode '0755'
end

# Install/remove core packages
#
node['datashades']['core']['unwanted-packages'].each do |p|
    package p do
        action :remove
    end
end

# Install packages that have different names on different systems
node['datashades']['core']['alternative_packages'].each do |p|
	bash "Install one of #{p}" do
		code <<-EOS
			if (yum info "#{p[0]}"); then
				yum install -y "#{p[0]}"
			else
				yum install -y "#{p[1]}"
			fi
		EOS
	end
end

package node['datashades']['core']['packages']

extra_disk = "/mnt/local_data"
extra_disk_present = ::File.exist? extra_disk

if extra_disk_present then
    real_cache_dir = "#{extra_disk}/.cache"

    directory real_cache_dir do
        mode '0755'
        recursive true
    end

    datashades_move_and_link('/root/.cache') do
        target real_cache_dir
    end
end

bash "Link 'pip' if not present" do
    code <<-EOS
        if ! (which pip); then
            PIP3=`which pip3`
            if [ "$PIP3" != "" ]; then
                ln -s "$PIP3" /usr/bin/pip
            fi
        fi
    EOS
end

execute "Update AWS command-line interface" do
    command "pip --cache-dir=/tmp/ install --upgrade awscli"
end

# real basic stuff needs to go in first so jq available for new stack params that uses jq early on
#
include_recipe "datashades::stackparams"

# Enable yum-cron so updates are downloaded on running nodes
#
if system('yum info yum-cron')
    service "yum-cron" do
        action [:enable, :start]
    end
else
    execute "Enable automatic DNF updates" do
        command "systemctl enable dnf-automatic-install.timer"
    end
end

# Tag the root EBS volume so we can manage it in AWS Backup etc.
#
bash "Tag root EBS volume" do
    code <<-EOS
        ROOT_DISK_ID=$(aws ec2 describe-volumes --region=#{node['datashades']['region']} --filters Name=attachment.instance-id,Values=#{node['datashades']['instid']} Name=attachment.device,Values=/dev/xvda --query 'Volumes[*].[VolumeId]' --out text | cut -f 1)
        aws ec2 create-tags --region #{node['datashades']['region']} --resources $ROOT_DISK_ID --tags Key=Name,Value=#{node['datashades']['hostname']}-root-volume Key=Environment,Value=#{node['datashades']['version']} Key=Service,Value=#{node['datashades']['sitename']} Key=Division,Value="Qld Online" Key=Owner,Value="Development and Delivery" Key=Version,Value="1.0"
    EOS
end

# Make sure all instances have an /etc/zoneid
#
bash "Adding AWS ZoneID" do
    user "root"
    code <<-EOS
    zoneid=$(aws route53 list-hosted-zones-by-name --dns-name "#{node['datashades']['tld']}" | jq '.HostedZones[0].Id' | tr -d '"/hostedzone')
    echo "zoneid=${zoneid}" > /etc/awszoneid
    EOS
end

# Push stats to enable Cloudwatch monitoring
#
cwmon_artifact = "CloudWatchMonitoringScripts-1.2.2.zip"
remote_file "/opt/aws/#{cwmon_artifact}" do
    source "https://aws-cloudwatch.s3.amazonaws.com/downloads/#{cwmon_artifact}"
    mode '0644'
end

execute 'Unzip CloudWatch monitoring scripts' do
    command "unzip -u -q /opt/aws/#{cwmon_artifact} -d /opt/aws/"
end

file "/etc/cron.d/cwpump" do
    content "*/5 * * * * root perl /opt/aws/aws-scripts-mon/mon-put-instance-data.pl --mem-util --mem-used --mem-avail --swap-util --disk-space-util --disk-space-avail --disk-path=/ --auto-scaling --from-cron\n"
    mode '0644'
end

# Replace default mail relay with Nuxeo AWS SMTP Relay
directory "/usr/share/aws-smtp-relay" do
    action :create
end

cookbook_file "/usr/share/aws-smtp-relay/aws-smtp-relay-1.0.0-jar-with-dependencies.jar" do
    source "aws-smtp-relay-1.0.0-jar-with-dependencies.jar"
end

template "/etc/init.d/aws-smtp-relay" do
    source "aws-smtp-relay.erb"
    mode "0755"
end

if system('yum info supervisor')
    package "supervisor"

    bash "Configure Supervisord" do
        user "root"
        cwd "/etc"
        code <<-EOS
            SUPERVISOR_CONFIG=supervisord.conf
            if ! [ -f "$SUPERVISOR_CONFIG" ]; then
                exit 0
            fi

            # configure Unix socket path
            UNIX_SOCKET=/var/tmp/supervisor.sock
            DEFAULT_UNIX_SOCKET=/var/run/supervisor/supervisor[.]sock
            if (grep "$DEFAULT_UNIX_SOCKET" $SUPERVISOR_CONFIG); then
                # if default config exists, update it
                sed -i "s|$DEFAULT_UNIX_SOCKET|$UNIX_SOCKET|g" $SUPERVISOR_CONFIG
            fi
            if ! (grep "unix_http_server" $SUPERVISOR_CONFIG); then
                # if no config exists, add it
                echo '[unix_http_server]' >> $SUPERVISOR_CONFIG
                echo "file = $UNIX_SOCKET" >> $SUPERVISOR_CONFIG
            fi
            if ! (grep "rpcinterface:supervisor" $SUPERVISOR_CONFIG); then
                echo '[rpcinterface:supervisor]' >> $SUPERVISOR_CONFIG
                echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> $SUPERVISOR_CONFIG
            fi

            # configure file inclusions
            SUPERVISOR_CONFIG_D=supervisord.d
            mkdir -p $SUPERVISOR_CONFIG_D

            LEGACY_SUPERVISOR_CONFIG_D="/etc/supervisor/conf.d/[*][.]conf"
            if (grep "$LEGACY_SUPERVISOR_CONFIG_D" $SUPERVISOR_CONFIG); then
                # if legacy config exists, update it
                sed -i "s|$LEGACY_SUPERVISOR_CONFIG_D|$SUPERVISOR_CONFIG_D/*.ini|g" $SUPERVISOR_CONFIG
            elif ! (grep "$SUPERVISOR_CONFIG_D" $SUPERVISOR_CONFIG); then
                # if no config exists, add it
                echo '[include]' >> $SUPERVISOR_CONFIG
                echo "files = $SUPERVISOR_CONFIG_D/*.ini" >> $SUPERVISOR_CONFIG
            fi
        EOS
    end

    # Configure either initd or systemd
    if system('which systemctl')
        systemd_unit "supervisord.service" do
            content({
                Unit: {
                    Description: 'Supervisor process control system for UNIX',
                    Documentation: 'http://supervisord.org',
                    After: 'network.target'
                },
                Service: {
                    ExecStart: '/usr/bin/supervisord -n -c /etc/supervisord.conf',
                    ExecStop: 'timeout 10s /usr/bin/supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; /usr/bin/supervisorctl $OPTIONS shutdown',
                    ExecReload: '/usr/bin/supervisorctl $OPTIONS reload',
                    KillMode: 'process',
                    Restart: 'on-failure',
                    RestartSec: '20s'
                },
                Install: {
                    WantedBy: 'multi-user.target'
                }
            })
            action [:create, :enable, :stop]
        end
    else
        service "supervisord" do
            action [:enable]
        end

        # Managed processes sometimes don't shut down properly on daemon stop,
        # leaving them 'orphaned' and resulting in duplicates.
        # Work around by issuing a stop command to the children first.
        execute "Stop children on supervisord stop" do
            command <<-'SED'.strip + " /etc/init.d/supervisord"
                sed -i 's/^\(\s*\)\(killproc\)/\1timeout 10s supervisorctl stop all || echo "WARNING: Unable to stop managed process(es) - check for orphans"; \2/'
            SED
        end
    end
end
