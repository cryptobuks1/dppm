class Service::OpenRC::Config
  getter section = Hash(String, String | Array(String) | Hash(String, Array(String))).new

  def initialize
    @section = base
  end

  def initialize(data : String, file = false)
    if file && File.exists? data
      parse File.read data
    elsif file
      @section = base
    else
      parse data
    end
  end

  def base
    {"pidfile"    => "/run/${RC_SVCNAME}.pid",
     "supervisor" => "supervise-daemon",
     "stdout"     => "log/out.log",
     "stderr"     => "log/err.log",
     "depend"     => {
       "after" => ["net"],
     },
     "reload" => ["eerror \"Reloading not available for $RC_SVCNAME\""]}
  end

  def shim(name)
    case name
    when "directory"     then ["chdir"]
    when "user"          then ["user"]
    when "group"         then ["group"]
    when "after"         then ["depend", "after"]
    when "want"          then ["depend", "want"]
    when "environment"   then ["env"]
    when "description"   then ["description"]
    when "restart_delay" then ["respawn_delay"]
    when "network"       then ["net"]
    when "umask"         then ["umask"]
    when "reload"        then ["reload"]
    when "pidfile"       then ["pidfile"]
    when "log_output"    then ["stdout"]
    when "log_error"     then ["stderr"]
    else
      raise "don't exist in openrc: " + name
    end
  end

  def get(name : String)
    if name == "command"
      return "#{@section["command"]} #{@section["command_args"]}"
    end
    keys = shim name
    case keys.size
    when 1 then @section[keys[0]]
    when 2
      subdata = @section[keys[0]]
      if subdata.is_a? Hash(String, String)
        subdata[keys[1]]
      else
        raise "unknown type: #{subdata}"
      end
    else
      raise "invalid keys: #{keys}"
    end
  end

  def set(name, value)
    case name
    when "command"
      command = value.split ' '
      @section["command"] = command[0]
      @section["command_args"] = command[1..-1].join ' '
    when "reload"
      @section["extra_started_commands"] = ["reload"]
      @section["reload"] = ["ebegin \"Reloading $RC_SVCNAME\"",
                            "supervise-daemon --signal #{value} --pidfile \"$pidfile\"",
                            "eend $? \"Failed to reload $RC_SVCNAME\""]
    else
      keys = shim name
      if keys.size == 1
        @section[keys[0]] = value
      elsif keys.size == 2
        subdata = @section[keys[0]]
        case subdata
        when .is_a? Hash(String, String)
          subdata[keys[1]] = value
        when .is_a? Hash(String, Array(String))
          subdata[keys[1]] << value
        else
          raise "unknown type: #{subdata}"
        end
        @section[keys[0]] = subdata
      else
        raise "only size of 0 and 1 is available: #{keys}"
      end
    end
  end

  def env_get(env)
    if env_section = @section["env"]?
      Service::Env.get env_section, env
    end
  end

  def env_set(env, value)
    @section["env"] = Service::Env.set @section["env"]?.to_s, env, value
  end
end
