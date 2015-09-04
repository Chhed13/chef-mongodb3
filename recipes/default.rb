#
# Cookbook Name:: mongodb3
# Recipe:: default
#
# Copyright 2015, Sunggun Yu
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'mongodb3::package_repo'

# Install MongoDB package
install_package = %w(mongodb-org-server mongodb-org-shell mongodb-org-tools)

# Setup package version to install
case node['platform_family']
  when 'rhel', 'fedora'
    package_version = "#{node['mongodb3']['version']}-1.el#{node.platform_version.to_i}" # ~FC019
  when 'debian'
    package_version = node['mongodb3']['version']
end

install_package.each do |pkg|
  package pkg do
    version package_version
    action :install
  end
end

# Create the paths if not exist.
[node['mongodb3']['config']['mongod']['storage']['dbPath'],
 File.dirname(node['mongodb3']['config']['mongod']['systemLog']['path']),
 File.dirname(node['mongodb3']['mongod']['config_file']),
 File.dirname(node['mongodb3']['config']['mongod']['processManagement']['pidFilePath'])].each do |path|
  directory path do
    owner node['mongodb3']['user']
    group node['mongodb3']['group']
    mode '0755'
    action :create
    recursive true
  end if path
end

unless node['mongodb3']['config']['key_file_content'].to_s.empty?
  # Create the key file if it is not exist
  key_file = node['mongodb3']['config']['mongod']['security']['keyFile']
  file key_file do
    content node['mongodb3']['config']['key_file_content']
    mode '0600'
    owner node['mongodb3']['user']
    group node['mongodb3']['group']
  end
end

# Update the mongodb config file
template node['mongodb3']['mongod']['config_file'] do
  source 'mongodb.conf.erb'
  mode 0644
  variables(
      :config => node['mongodb3']['config']['mongod']
  )
  helpers Mongodb3Helper
end

#special init script for CentOS7
need_rhel7_fix = platform_family?('rhel') && node['platform_version'].to_i >= 7
#Set Ulimits for CentOS7
cookbook_file '/etc/security/limits.d/99-mongodb-nproc.conf' do
  source "99-mongodb-nproc.conf"
  mode 0644
  only_if { need_rhel7_fix }
end
#https://jira.mongodb.org/browse/SERVER-18439
template "/etc/init.d/mongod" do
  source "mongod.init.erb"
  owner "root"
  group "root"
  mode 0755
  variables(
      :skip_redirect => false,
      :pid_file      => node['mongodb3']['config']['mongod']['processManagement']['pidFilePath'],
      :config_file   => node['mongodb3']['mongod']['config_file'],
      :user          => node['mongodb3']['user'],
      :group         => node['mongodb3']['group']
  )
  notifies :run, 'execute[mongodb-systemctl-daemon-reload]', :immediately
  only_if { need_rhel7_fix }
end

# Reload systemctl for RHEL 7+ after modifying the init file.
execute 'mongodb-systemctl-daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

# Start the mongod service
service 'mongod' do
  supports :start => true, :stop => true, :restart => true, :status => true
  action :enable
  subscribes :restart, "template[#{node['mongodb3']['mongod']['config_file']}]", :delayed
  subscribes :restart, "template[#{node['mongodb3']['config']['mongod']['security']['keyFile']}", :delayed
  subscribes :restart, "template[/etc/init.d/mongod]", :delayed
end