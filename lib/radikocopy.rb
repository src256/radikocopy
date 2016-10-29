# coding: utf-8
require "radikocopy/version"
require 'yaml'
require "optparse"

module Radikocopy
  class Config
    def initialize(config)
      @config = config
      @remote_host = config_value("remote", "host", false)
      @remote_dir = config_value("remote", "dir", false)
      @local_dir = config_value("local", "dir", true)
      dir = File.dirname(File.expand_path(__FILE__))
      @import_scpt = File.join(dir, "radikoimport.scpt")
    end

    attr_reader :remote_host, :remote_dir, :local_dir, :import_scpt

    def to_s
      str = ''
      str << "remote_host: #{remote_host}\n"
      str << "remote_dir: #{remote_dir}\n"
      str << "local_dir: #{local_dir}\n"
      str << "import_scpt: #{import_scpt}\n"      
    end

    def local_only?
      @remote_host.nil? || @remote_dir.nil?
    end
    
    private
    def config_value(section, key, require)
      value = @config[section][key]
      if require && (value.nil? || value.empty?)
        raise RuntimeError, "#{section}:#{key}: is empty"
      end
      value
    end
  end

  class Command
    def self.run(argv)
      STDOUT.sync = true
      opts = {}
      opt = OptionParser.new(argv)
      opt.banner = "Usage: #{opt.program_name} [-h|--help] config.yml"
      opt.separator('')
      opt.separator "#{opt.program_name} Available Options"
      opt.on_head('-h', '--help', 'Show this message') do |v|
        puts opt.help
        exit
      end
      opt.on('-v', '--verbose', 'Verbose message') {|v| opts[:v] = v}
      opt.on('-n', '--dry-run', 'Message only') {|v| opts[:n] = v}
      opt.on('-f', '--force-import', 'Force import') {|v| opts[:f] = v} 
      opt.parse!(argv)
      if argv.empty?
        puts opt.help
        exit
      end
      config = Config.new(YAML.load_file(argv[0]))
      puts config
      radikocopy = Command.new(opts, config)
      radikocopy.run
    end
    
    def initialize(opts, config)
      @opts = opts
      @config = config
    end
    
    def run
      puts "##### start radikocopy #####"
      filenames = []
      if @opts[:f] || @config.local_only?
        filenames = Dir.glob("#{@config.local_dir}/*.mp3")
      else
        filenames = copy_files
      end
      import_files(filenames)
      puts "##### end radikocopy #####" 
    end

    def copy_files
      # リモートホスト内の録音ファイルをローカルにコピー
      list_command = "ssh #{@config.remote_host} 'find \"#{@config.remote_dir}\"'"
      puts list_command
      result = `#{list_command}`
      files = []
      result.each_line do |line|
        line.chomp!
        if line =~ /mp3$/
          if copy_file(line)
            basename = File.basename(line)
            files << File.join(@config.local_dir, basename)
          end
        end
      end
      files
    end

    def copy_file(filename)
      basename = File.basename(filename)
      local_file = File.join(@config.local_dir, basename)
      if FileTest.file?(local_file)
        puts "exists local_file #{local_file}"
        return false
      end
      copy_command = "scp #{@config.remote_host}:\"'#{filename}'\" \"#{@config.local_dir}\""
      runcmd(copy_command)
      true
    end

    def import_files(files)
      files.each do |file|
        cmd = "osascript #{@config.import_scpt} \"#{file}\""
        runcmd(cmd)
      end
    end

    def runcmd(cmd)
      puts cmd
      unless system(cmd)
        puts "system error"
        exit(1)
      end
    end
  end

end
