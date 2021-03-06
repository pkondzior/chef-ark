#
# Cookbook Name:: ark
# Provider:: ArkBase
#
# Author:: Bryan W. Berry <bryan.berry@gmail.com>
# Copyright 2012, Bryan W. Berry
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
#

require 'chef/provider'

class Chef
  class Provider
    class ArkBase < Chef::Provider
      
      def load_current_resource
        @current_resource = Chef::Resource::ArkBase.new(@new_resource.name)
      end
      
      def action_download
        
        unless new_resource.url =~ /^(http|ftp).*$/
            new_resource.url = set_apache_url(url)
        end
        f = Chef::Resource::RemoteFile.new(new_resource.release_file, run_context)
        f.source new_resource.url
        if new_resource.checksum
          f.checksum new_resource.checksum
        end
        f.run_action(:create)
      end
      
      def action_install
        set_paths
        action_download
        action_unpack
        action_set_owner
        action_install_binaries
      end

      def action_unpack
        d = Chef::Resource::Directory.new(new_resource.path, run_context)
        d.mode '0755'
        d.recursive true
        d.run_action(:create)
        expand_cmd unless exists?
      end

      def action_set_owner
        require 'fileutils'
        FileUtils.chown_R new_resource.owner, new_resource.owner, new_resource.path
      end

      def action_install_binaries
        if not new_resource.has_binaries.empty?
          new_resource.has_binaries.each do |bin|
            file_name = ::File.join('/usr/local/bin', ::File.basename(bin))
            
            l = Chef::Resource::Link.new(file_name, run_context)
            
            l.to ::File.join(new_resource.path, bin)
            l.run_action(:create)
          end
        elsif new_resource.append_env_path
          new_path = ::File.join(new_resource.path, 'bin')
          Chef::Log.debug("new_path is #{new_path}")
          
          path = "/etc/profile.d/#{new_resource.name}.sh"
          f = Chef::Resource::File.new(path, run_context)
          f.content <<-EOF
          export PATH=$PATH:#{new_path}
          EOF
          f.mode 0755
          f.owner 'root'
          f.group 'root'
          f.run_action(:create)
          ENV['PATH'] = ENV['PATH'] + ':' + ::File.join(new_resource.path, 'bin')
          Chef::Log.debug("PATH after setting_path  is #{ENV['PATH']}")
        end
      end
      
      private

      def exists?
        if new_resource.creates and !(new_resource.creates.empty?)
          if  ::File.exist?(::File.join(new_resource.path,
                                        new_resource.creates))
            true
          else
            false
          end
        elsif !::File.exists?(new_resource.path) or
            ::File.stat("#{new_resource.path}/").nlink == 2
          false
        else
          true
        end
      end

      def expand_cmd
        case parse_file_extension
        when 'tar.gz'  then untar_cmd('xzf')
        when 'tar.bz2' then untar_cmd('xjf')
        when /zip|war|jar/ then unzip_cmd
        else raise "Don't know how to expand #{new_resource.url} which has extension '#{release_ext}'"
        end
      end

      def set_paths
        release_ext = parse_file_extension
        new_resource.path      = ::File.join(new_resource.path, "#{new_resource.name}")
        Chef::Log.debug("path is #{new_resource.path}")
        new_resource.release_file     = ::File.join(Chef::Config[:file_cache_path],  "#{new_resource.name}.#{release_ext}")
      end
      
      def parse_file_extension
        release_basename = ::File.basename(new_resource.url.gsub(/\?.*\z/, '')).gsub(/-bin\b/, '')
        # (\?.*)? accounts for a trailing querystring
        release_basename =~ %r{^(.+?)\.(tar\.gz|tar\.bz2|zip|war|jar)(\?.*)?}
        $2
      end
      
      def set_apache_url(url_ref)
        raise "Missing required resource attribute url" unless url_ref
        url_ref.gsub!(/:name:/,          name.to_s)
        url_ref.gsub!(/:version:/,       version.to_s)
        url_ref.gsub!(/:apache_mirror:/, node['install_from']['apache_mirror'])
        url_ref
      end

      
      def unzip_cmd
          FileUtils.mkdir_p new_resource.path
          if new_resource.strip_leading_dir
            require 'tmpdir'
            tmpdir = Dir.mktmpdir
            cmd = Chef::ShellOut.new("unzip  -q -u -o '#{new_resource.release_file}' -d '#{tmpdir}'")
            cmd.run_command
            cmd.error!
            subdirectory_children = Dir.glob("#{tmpdir}/**")
            FileUtils.mv subdirectory_children, new_resource.path
            FileUtils.rm_rf tmpdir
          else
            cmd = Chef::ShellOut.new("unzip  -q -u -o #{new_resource.release_file} -d #{new_resource.path}")
            cmd.run_command
            cmd.error!
          end 
      end

      def untar_cmd(sub_cmd)
          FileUtils.mkdir_p new_resource.path
          if new_resource.strip_leading_dir
            strip_argument = "--strip-components=1"
          else
            strip_argument = ""
          end
          
          b = Chef::Resource::Script::Bash.new(new_resource.name, run_context)
          cmd = %Q{tar -#{sub_cmd} #{new_resource.release_file} #{strip_argument} -C #{new_resource.path} }
          b.flags "-x"
          b.code <<-EOH
          tar -#{sub_cmd} #{new_resource.release_file} #{strip_argument} -C #{new_resource.path}
          EOH
          b.run_action(:run)
      end

    end
  end
end

