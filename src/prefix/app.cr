require "./program_data"

struct Prefix::App
  include ProgramData

  getter logs_dir : String,
    log_file_output : String,
    log_file_error : String

  getter password : String? do
    if File.exists? password_file
      File.read password_file
    end
  end

  getter password_file : String do
    conf_dir + "password"
  end

  getter pkg : Pkg do
    Pkg.new @prefix, File.basename(File.dirname(File.real_path(app_path))), nil, @pkg_file
  end

  @service_intialized = false

  def service? : Service::OpenRC | Service::Systemd | Nil
    if !@service_intialized
      if service = Service.init?
        @service = service.new @name
      end
      @service_intialized = true
    end
    @service
  end

  getter service : Service::OpenRC | Service::Systemd do
    service? || raise "service not available"
  end

  getter service_dir : String do
    conf_dir + "init/"
  end

  getter service_file : String do
    service_dir + service.type
  end

  def service_tap(&block : Service::OpenRC | Service::Systemd -> Service::OpenRC | Service::Systemd)
    @service = yield service
  end

  def service_create(user : String, group : String, database_name : String? = nil)
    (exec = pkg_file.exec) || raise "exec key not present in #{pkg_file.path}"

    Dir.mkdir_p service_dir

    Log.info "creating system service", @name

    # Set service options
    service_tap do |service|
      service.config_tap do |config|
        config.user = user
        config.group = group
        config.directory = path
        config.description = pkg_file.description
        config.log_output = log_file_output
        config.log_error = log_file_error
        config.command = path + exec["start"]
        config.after << database_name if database_name

        # add a reload directive if available
        if exec_reload = exec["reload"]?
          config.reload_signal = exec_reload
        end

        # Add a PATH environment variable if not empty
        if !(path_var = path_env_var).empty?
          config.env_vars["PATH"] = path_var
        end
        if pkg_env = pkg_file.env
          config.env_vars.merge! pkg_env
        end

        # Convert back hashes to service files
        config
      end
      File.write service_file, service.config_build
      service
    end
  end

  def service_enable
    service.link service_file
  end

  def database? : Database::MySQL | Nil
    @database
  end

  getter database : Database::MySQL | Nil do
    if pkg_file.config.has_key?("database_address")
      uri = URI.parse "//#{get_config("database_address")}"
    elsif pkg_file.config.has_key?("database_host")
      uri = URI.new(
        host: get_config("database_host").to_s,
        port: get_config("database_port").to_s.to_i,
      )
    else
      return
    end
    type = get_config("database_type").to_s
    return if !Database.supported? type

    uri.password = get_config("database_password").to_s
    uri.user = user = get_config("database_user").to_s

    Database.new_database uri, user, type
  end

  def database=(database_app : App)
    @database = Database.create @prefix, @name, database_app
  end

  protected def initialize(@prefix : Prefix, @name : String, pkg_file : PkgFile? = nil)
    @path = @prefix.app + @name + '/'
    if pkg_file
      pkg_file.path = nil
      pkg_file.root_dir = @path
      @pkg_file = pkg_file
    end
    @logs_dir = @path + "log/"
    @log_file_output = @logs_dir + "output.log"
    @log_file_error = @logs_dir + "error.log"
  end

  def set_config(key : String, value)
    config.set pkg_file.config[key], value
  end

  def del_config(key : String)
    config.del pkg_file.config[key]
  end

  def real_app_path : String
    File.dirname File.real_path(app_path)
  end

  def log_file(error : Bool = false)
    error ? @log_file_error : @log_file_output
  end

  def set_permissions
    File.chmod conf_dir, 0o700
    File.chmod data_dir, 0o750
    File.chmod logs_dir, 0o700
  end

  def each_lib(&block : String ->)
    if Dir.exists? libs_dir
      Dir.each_child(libs_dir) do |lib_package|
        yield File.real_path(libs_dir + lib_package) + '/'
      end
    end
  end

  def path_env_var : String
    String.build do |str|
      str << app_path << "/bin"
      if Dir.exists? libs_dir
        Dir.each_child(libs_dir) do |library|
          str << ':' << libs_dir << library << "/bin"
        end
      end
    end
  end
end
