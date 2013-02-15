require 'rinda/ring'
require 'rinda/tuplespace'
require 'ringy_dingy'
require 'optparse'

##
# RingyDingy::RingServer provides a friendly wrapper around Rinda::RingServer.
#
# When running on the command line, RingyDingy::RingServer's verbose mode may
# be toggled remotely via the --set-verbose option.
#
# = Usage
#
# == Starting a RingServer
#
# From the command line:
#
#   ring_server -d
#
# or from Ruby:
#
#   RingyDingy::RingServer.new.run
#
# == List Services
#
# From the command line (after starting a RingServer):
#
#   ring_server -l
#
# or from Ruby:
#
#   RingyDingy::RingServer.list
#
# == Verbose mode
#
# Changing verbose mode for the server (when not a daemon).
#
#   ring_server --set-verbose=true/false
#
# or from Ruby:
#
#   RingyDingy::RingServer.set_verbose true/false

class RingyDingy::RingServer

  ##
  # Verbose setting for this RingyDingy::RingServer.

  attr_reader :verbose

  ##
  # The Rinda::TupleSpace where services are registered

  attr_reader :service_registry

  @ring_finger = Rinda::RingFinger.new

  class << self
    ##
    # Overrides the Rinda::RingFinger used for class methods.

    attr_accessor :ring_finger
  end

  ##
  # Return a collection of all remote DRb services.
  #
  # Format:
  #
  #   { Rinda::RingServer.__drburi => [ registration_tuple, ... ],
  #     ... }

  def self.list_services
    DRb.start_service unless DRb.primary_server

    services = {}

    @ring_finger.lookup_ring do |ts|
      services[ts.__drburi] = ts.read_all [:name, nil, DRbObject, nil]
    end

    return services
  end

  ##
  # Print all available services on all available Rinda::RingServers to
  # stdout.

  def self.print_services
    DRb.start_service unless DRb.primary_server

    out = []
    list_services.each do |ring_server, services|
      out << "Services on #{ring_server}"

      values = services.sort_by { |s| [s[2].__drburi, -s[2].__drbref] }

      values.each do |s|
        out << "\t%p, %p\n\t\tURI: %s ref: %d" %
               [s[1], s[3], s[2].__drburi, s[2].__drbref]
        out << nil
      end
    end

    puts out.join("\n")
  end

  ##
  # Enables or disables verobse mode on all available Rinda::RingServers
  # depending upon +boolean+.

  def self.set_verbose(boolean)
    DRb.start_service unless DRb.primary_server

    @ring_finger.lookup_ring do |ts|
      ts.write [:RingyDingy, :verbose, boolean]
    end
  end

  ##
  # Process +args+ into an options Hash.  See also #new.

  def self.process_args(args)
    options = {}
    options[:Verbose] = false

    op = OptionParser.new do |opt|
      opt.program_name = 'ring_server'
      opt.version = RingyDingy::VERSION
      opt.release = nil

      opt.banner = "Usage: #{name} [options]"
      opt.separator ''
      opt.separator 'Run, find, or modify the behavior of a Rinda::RingServer.'
      opt.separator ''
      opt.separator 'With no arguments a Rinda::RingServer is started and runs in the foreground.'
      opt.separator ''

      opt.separator 'RingServer options:'
      opt.on("-d", "--daemon",
             "Run a RingServer as a daemon") do |val|
        options[:Daemon] = val
      end

      opt.on("-v", "--verbose",
             "Enable verbose mode") do |val|
        options[:Verbose] = val
      end

      opt.separator ''
      opt.separator 'Miscellaneous options:'

      opt.on("-l", "--list",
             "List services on available RingServers") do |val|
        options[:List] = val
      end

      opt.on(      "--set-verbose=BOOLEAN", TrueClass,
             "Enable or disable verbose mode on available",
             "RingServers (except daemon RingServers)") do |val|
        options[:SetVerbose] = val
      end
    end

    op.parse! args

    return options
  end

  ##
  # Run appropriately.

  def self.run(args = ARGV)
    options = process_args args

    if options.include? :List then
      print_services
      exit
    elsif options.include? :SetVerbose and options.include? :Daemon then
      abort '--daemon with --verbose sends output to /dev/null'
    elsif options.include? :SetVerbose then
      set_verbose options[:SetVerbose]
      exit
    elsif options.include? :Daemon then
      require 'webrick/server'
      WEBrick::Daemon.start
    end

    new(options).run
  end

  ##
  # Prints usage message +message+ if present then OptionParser +op+.

  def self.usage(op, message = nil)
    if message then
      $stderr.puts message
      $stderr.puts
    end

    $stderr.puts op
    exit 1
  end

  ##
  # Creates a new RingyDingy::RingServer.
  #
  # +options+ may contain:
  # [:Daemon] In daemon-mode #verbose may not be changed.
  # [:Verbose] In verbose mode service registrations and expirations are
  #            logged to $stderr.

  def initialize options = {}
    @service_registry = Rinda::TupleSpace.new

    @registrations = nil
    @expirations = nil

    @daemon = options[:Daemon]

    @verbose = nil
    self.verbose = options[:Verbose] and not @daemon
  end

  ##
  # Disables service registration and expiration logging.

  def disable_activity_logging
    @registrations.cancel if @registrations and @registrations.alive?
    @expirations.cancel if @expirations and @expirations.alive?

    $stderr.puts 'registration and expiration logging disabled'
  end

  ##
  # Enables service registration and expiration logging.

  def enable_activity_logging
    log 'registration and expiration logging enabled'

    @registrations = @service_registry.notify 'write', [:name, nil, DRbObject, nil]
    @expirations = @service_registry.notify 'delete', [:name, nil, DRbObject, nil]

    Thread.start do
      @registrations.each do |(_,t)|
        $stderr.puts "registered %p, %p\n\tURI: %s ref: %d" %
                       [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end

    Thread.start do
      @expirations.each do |(_,t)|
        $stderr.puts "expired %p, %p\n\tURI: %s ref: %d" %
                       [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end
  end

  ##
  # Logs a message to $stderr when @verbose is true.

  def log(message)
    return unless @verbose
    $stderr.puts message
  end

  ##
  # Worker thread to monitor remote toggling of verbose mode.

  def monitor_verbose
    Thread.start do
      loop do
        self.verbose = @service_registry.take([:RingyDingy, :verbose, nil])[2]
      end
    end
  end

  ##
  # Starts a new RingyDingy::RingServer.

  def run
    DRb.start_service unless DRb.primary_server

    log "listening on #{DRb.uri}"

    monitor_verbose

    Rinda::RingServer.new @service_registry

    DRb.thread.join
  end

  ##
  # Sets verbose to +value+ when @daemon is not true.

  def verbose=(value)
    return if @verbose == value
    @verbose = value
    @verbose ? enable_activity_logging : disable_activity_logging
    @verbose
  end

end

