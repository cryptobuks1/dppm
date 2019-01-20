require "./config"

struct Service::OpenRC::Config
  include Service::Config

  def initialize(data : String)
    line_number = 1
    function_name = ""

    data.each_line do |full_line|
      case line = full_line.lstrip "\n\t "
      when .ends_with? '}'                then function_name = ""
      when .ends_with? "() {"             then function_name = line.rchop "() {"
      when .starts_with? "description="   then @description = line.lchop("description='").rchop
      when .starts_with? "directory="     then @directory = line.lchop("directory='").rchop
      when .starts_with? "umask="         then @umask = line.lchop "umask="
      when .starts_with? "output_log="    then @log_output = line.lchop("output_log='").rchop
      when .starts_with? "error_log="     then @log_error = line.lchop("error_log='").rchop
      when .starts_with? "respawn_delay=" then @restart_delay = line.lchop("respawn_delay=").to_u32
      when .starts_with? "command="
        @command = line.lchop("command='").rchop + @command.to_s
      when .starts_with? "command_args="
        @command = @command.to_s + ' ' + line.lchop("command_args='").rchop
      when .starts_with? "command_user="
        user_and_group = line.lchop("command_user='").rchop.split ':', limit: 2
        @user = user_and_group[0]?
        @group = user_and_group[1]?
      when .starts_with? OPENRC_ENV_VARS_PREFIX
        parse_env_vars line.lchop(OPENRC_ENV_VARS_PREFIX).rchop("'\"")
      when .empty?,
           OPENRC_SHEBANG,
           OPENRC_SUPERVISOR,
           OPENRC_PIDFILE,
           "\"",
           .starts_with?("extra_started_commands"),
           .starts_with?("pidfile")
      else
        case function_name
        when "depend"
          values = line.split ' '
          case values[0]
          when "after"  then @after = values[1..-1]
          when "before" then @before = values[1..-1]
          when "want"   then @want = values[1..-1]
          else               raise "unsupported line depend directive"
          end
        when "reload"
          if line.starts_with? OPENRC_RELOAD_COMMAND
            @reload_signal = line.lchop OPENRC_RELOAD_COMMAND
          end
        else
          raise "unsupported line"
        end
      end
      line_number += 1
    rescue ex
      raise "parse error line at #{line_number}: #{full_line}\n#{ex}"
    end
  end

  def build
    to_openrc
  end
end

module Service::Config
  private OPENRC_RELOAD_COMMAND  = "supervise-daemon --pidfile \"$pidfile\" --signal "
  private OPENRC_PIDFILE         = "pidfile=\"/run/${RC_SVCNAME}.pid\""
  private OPENRC_SHEBANG         = "#!/sbin/openrc-run"
  private OPENRC_SUPERVISOR      = "supervisor=supervise-daemon"
  private OPENRC_ENV_VARS_PREFIX = "supervise_daemon_args=\"--env '"

  def to_openrc : String
    String.build do |str|
      str << OPENRC_SHEBANG << "\n\n"
      str << OPENRC_SUPERVISOR << '\n'
      str << OPENRC_PIDFILE
      str << "\nextra_started_commands=reload" if @reload_signal
      str << "\ncommand_user='#{@user}:#{@group}'" if @user || @group
      str << "\ndirectory='" << @directory << '\'' if @directory
      if command = @command
        command_elements = command.split ' ', limit: 2
        str << "\ncommand='" << command_elements[0] << '\''
        if command_args = command_elements[1]?
          str << "\ncommand_args='" << command_args << '\''
        end
      end
      str << "\noutput_log='" << @log_output << '\'' if @log_output
      str << "\nerror_log='" << @log_error << '\'' if @log_error
      str << "\ndescription='" << @description << '\'' if @description
      str << "\nrespawn_delay=" << @restart_delay if @restart_delay
      str << "\numask=" << @umask if @umask

      if !@env_vars.empty?
        str << '\n' << OPENRC_ENV_VARS_PREFIX
        build_env_vars str
        str << "'\""
      end

      str << "\n\ndepend() {\n\tafter "
      if !@after.empty?
        @after.join ' ', str
        str << '\n'
      else
        str << "net\n"
      end
      if !@before.empty?
        @before.join ' ', str
        str << '\n'
      end
      if !@want.empty?
        @want.join ' ', str
        str << '\n'
      end
      str << "}\n"

      if @reload_signal
        str << <<-E

        reload() {
        \tebegin "Reloading $RC_SVCNAME"
        \t#{OPENRC_RELOAD_COMMAND}#{@reload_signal}
        \teend $? "Failed to reload $RC_SVCNAME"
        }
        
        E
      end
    end
  end
end