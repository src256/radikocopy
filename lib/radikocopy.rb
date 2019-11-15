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
      unless FileTest.directory?(@local_dir)
        raise RuntimeError, "local_dir does not exists: #{@local_dir}"
      end
      dir = File.dirname(File.expand_path(__FILE__))
      if FileTest.exist?('/System/Applications/Music.app')
        @import_scpt = File.join(dir, "radikoimport_music.scpt")
      else
        @import_scpt = File.join(dir, "radikoimport_itunes.scpt")
      end
      @keep = 20
    end

    attr_reader :remote_host, :remote_dir, :local_dir, :import_scpt, :keep

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
      opt.banner = "Usage: #{opt.program_name} [-h|--help] [config.yml]"
      opt.version = Radikocopy::VERSION
      opt.separator('')
      opt.separator "Options:"
      opt.on_head('-h', '--help', 'Show this message') do |v|
        puts opt.help
        exit
      end
      opt.on('-v', '--verbose', 'Verbose message') {|v| opts[:v] = v}
      opt.on('-n', '--dry-run', 'Message only') {|v| opts[:n] = v}
      opt.on('-f', '--force-import', 'Force import') {|v| opts[:f] = v} 
      opt.parse!(argv)

      # 最後の引数は設定ファイルのパス
      config_file = argv.empty? ? "~/.radikocopyrc" : argv[0]
      config_file = File.expand_path(config_file)
      unless FileTest.file?(config_file)
        puts opt.help
        exit
      end
      config = Config.new(YAML.load_file(config_file))
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
        filenames = Dir.glob("#{@config.local_dir}/*.{mp3,m4a}")
      else
        filenames = copy_files
      end
      import_files(filenames)
      expire_local_files
      puts "##### end radikocopy #####" 
    end

    def copy_files
      # リモートホスト内の録音ファイルをローカルにコピー
      list_command = "ssh #{@config.remote_host} 'find \"#{@config.remote_dir}\"'"
      puts list_command
      result = `#{list_command}`
      files = []
      result.each_line do |line|
#        puts line
        line.chomp!
        if line =~ /mp3$/ || line =~ /m4a$/
          if copy_file(line)
            basename = File.basename(line)
            local_file = File.join(@config.local_dir, basename)
            puts "local_file: #{local_file}"
            files << local_file
          end
        end
      end
      files
    end

    def copy_file(filename)
      basename = File.basename(filename)
      local_file = File.join(@config.local_dir, basename)
#      puts  "##### local_file #{local_file} #####"
      if FileTest.file?(local_file)
# TODO -v option        
#        puts "exists local_file #{local_file}"
        return false
      end
#      puts "not exists"
      copy_command = "scp -p #{@config.remote_host}:\"'#{filename}'\" \"#{@config.local_dir}\""
      runcmd_and_exit(copy_command)
      true
    end

    def import_files(files)
      files.each do |file|
        import_ok = false
        3.times do |i|
          if import_file(file, i)
            import_ok = true
            break
          end
          sleep(1)
        end
        unless import_ok
          puts "import failed"
          File.unlink(file)
        end
      end
    end

    def import_file(file, i)
      cmd = "osascript #{@config.import_scpt} \"#{file}\""
      unless runcmd(cmd)
        puts "import error[#{i}] #{file}"
        return false
      end
      true
    end

    def expire_local_files
      #ローカル保存フォルダ内の古いファイルを削除する
      filenames = Dir.glob("#{@config.local_dir}/*.{mp3,m4a}").sort_by {|f| File.mtime(f) }.reverse
      filenames.each_with_index do |filename, index|
        if index < @config.keep
          puts "Keep: #{filename}"
        else
          puts "Delete: #{filename}"
          File.unlink(filename)
        end
      end
    end
    
    def runcmd_and_exit(cmd)
      unless runcmd(cmd)
        puts "system error"
        exit(1)        
      end
    end

    def runcmd(cmd)
      puts cmd
      system(cmd)
    end    
  end

end
