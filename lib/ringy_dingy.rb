require 'English'
require 'drb'
require 'rinda/ring'

##
# RingyDingy registers a DRb service with a Rinda::RingServer and re-registers
# the service if communication with the Rinda::RingServer is ever lost.
#
# Similarly, if the Rinda::RingServer should ever lose contact with the
# service the registration will be automatically dropped after a short
# timeout.
#
# = Example
#
#   my_service = MyService.new
#   rd = RingyDingy.new my_service, :MyService
#   rd.run
#   DRb.thread.join

class RingyDingy

  ##
  # The version of RingyDingy you are using

  VERSION = '1.5'

  ##
  # Interval to check the RingServer for our registration information.

  attr_accessor :check_every

  ##
  # RingyDingy service identifier.  Use this to distinguish between
  # RingyDingys registering the same service.

  attr_reader :identifier

  ##
  # The object being provided by RingyDingy

  attr_reader :object

  ##
  # RingyDingy run loop thread.

  attr_reader :thread

  attr_accessor :ring_finger, :renewer # :nodoc:
  attr_writer :ring_server, :thread # :nodoc:

  ##
  # Lists of hosts to search for ring servers.  By default includes the subnet
  # broadcast address and localhost.

  BROADCAST_LIST = %w[<broadcast> localhost]

  ##
  # Finds the first live service matching +service_name+ on any ring server.
  # Ring servers are discovered via the +broadcast_list+.

  def self.find service_name, broadcast_list = BROADCAST_LIST
    RingyDingy::Lookup.new(broadcast_list).find service_name
  end

  ##
  # Creates a new RingyDingy that registers +object+ as +service+ with
  # optional identifier +name+.

  def initialize object, service = :RingyDingy, name = nil,
                 broadcast_list = BROADCAST_LIST
    DRb.start_service unless DRb.primary_server

    @identifier = [Socket.gethostname.downcase, $PID, name].compact.join '_'
    @object = object
    @service = service || :RingyDingy

    @check_every = 15
    @renewer = Rinda::SimpleRenewer.new

    @ring_finger = Rinda::RingFinger.new broadcast_list
    @ring_server = nil

    @thread = nil
  end

  ##
  # Registers this service with the primary Rinda::RingServer.

  def register
    reference = DRb::DRbObject.new(@object)

    tuple = [:name, @service, reference, @identifier]

    ring_server.write tuple, @renewer

    nil
  end

  ##
  # Looks for a registration tuple in the primary Rinda::RingServer.  If a
  # RingServer can't be found or contacted, returns false.

  def registered?
    registrations = ring_server.read_all [:name, @service, nil, @identifier]
    registrations.any? { |registration| registration[2] == @object }
  rescue DRb::DRbConnError
    @ring_server = nil
    return false
  end

  if RUBY_VERSION >= '2' then
    ##
    # Looks up the primary Rinde::RingServer.

    def ring_server
      return @ring_server unless @ring_server.nil?
      @ring_server = @ring_finger.lookup_ring_any
    end
  else
    ##
    # Work around [ruby-talk:395364]

    def ring_server # :nodoc:
      require 'timeout'
      Timeout.timeout 5 do
        return @ring_server unless @ring_server.nil?
        @ring_server = @ring_finger.lookup_ring_any
      end
    rescue Timeout::Error
      raise 'RingNotFound'
    end
  end

  ##
  # Starts a thread that checks for a registration tuple every #check_every
  # seconds.
  #
  # If +wait+ is +:none+ (the default) run returns immediately.  If +wait+ is
  # +:first_register+ then run blocks until the service was successfully
  # registered.

  def run wait = :none
    mutex = Mutex.new
    service_registered = ConditionVariable.new

    @thread = Thread.start do
      loop do
        begin
          register unless registered?

          mutex.synchronize do
            service_registered.signal
          end if wait == :first_register
        rescue DRb::DRbConnError
          @ring_server = nil
        rescue RuntimeError => e
          raise unless e.message == 'RingNotFound'
        end
        sleep @check_every
      end
    end

    mutex.synchronize do
      service_registered.wait mutex
    end if wait == :first_register

    self
  end

  ##
  # Stops checking for registration tuples.

  def stop
    @thread.kill
    return nil
  end

end

require 'ringy_dingy/cancelable_renewer'
require 'ringy_dingy/lookup'
