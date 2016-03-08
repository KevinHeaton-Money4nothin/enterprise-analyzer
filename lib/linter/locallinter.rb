class LocalLinter
  include Common
  include Gitbase
  include Linter

  def initialize(git_dir, commit, log_prefix, linter_config_path, excluded_dirs, remove_open_source = true)
    @logger = BlissLogger.new(nil, nil, log_prefix)
    @git_dir = git_dir.nil? ? '/repository' : File.expand_path(git_dir)
    @linter_config_path = linter_config_path.nil? ? '/linter.yml' : File.expand_path(linter_config_path)
    @commit = commit
    @name = log_prefix
    @excluded_dirs = begin
                       excluded_dirs.split(',')
                     rescue
                       []
                     end
    @remove_open_source = remove_open_source
    @output_file = '/result.txt'
    @api_key = nil
    @repo_key = nil
    check_args
    @linter = YAML.load_file(@linter_config_path)
  end

  def execute
    checkout_commit(@git_dir, @commit)
    remove_excluded_directories(@excluded_dirs, @git_dir)
    remove_open_source_files(@git_dir) if @remove_open_source == true || @remove_open_source.nil?
    remove_symlinks(@git_dir)
    start = Time.now
    partition_and_lint
    time = Time.now - start
    @logger.info("\tTook #{time} seconds to run #{@linter['quality_tool']}...")
  end

  def partition_and_lint
    if @linter['partionable']
      parts = Partitioner.new(@git_dir, @logger).create_partitions
      @logger.info("\tRunning #{@linter['quality_tool']} on #{@commit}... This may take a while...")
      Parallel.each_with_index(parts, in_processes: parts.size) do |part, index|
        lint_commit(@linter, "/resultpart#{index}.txt", false, part)
      end
      consolidate_output
    else
      @logger.info("\tRunning #{@linter['quality_tool']} on #{@commit}... This may take a while...")
      lint_commit(@linter, @output_file, false, @git_dir)
    end
  end

  def consolidate_output
    File.truncate(@output_file, 0)
    Dir.glob('/resultpart*.txt').each do |r|
      File.open(@output_file, 'a') do |f|
        f.write("<--LintFilePartition-->\n#{File.read(r)}")
      end
    end
  end

  def check_args
    valid = true
    if !File.exist? @git_dir
      @logger.error('Directory does not exist.')
      valid = false
    elsif @output_file.nil? || !File.exist?(@output_file)
      @logger.error('Please specify a writable file to output to.')
      valid = false
    elsif File.directory?(@output_file)
      @logger.error('Output file is a directory. Should be a file.')
      valid = false
    elsif @linter_config_path.nil? || !File.exist?(@linter_config_path)
      @logger.error('Linter config file does not exist.')
      valid = false
    elsif File.directory?(@linter_config_path)
      @logger.error('Linter config path is a directory. Should be a file.')
      valid = false
    elsif @commit.nil? || @commit.empty?
      @logger.error('Please specify a commit.')
      valid = false
    end
    exit 1 unless valid
  end
end
