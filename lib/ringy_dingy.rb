require 'English'
require 'drb'
require 'rinda/ring'

$TESTING = false unless defined? $TESTING

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

  VERSION = '1.3'

  ##
  # Interval to check the RingServer for our registration information.

  attr_accessor :check_every

  ##
  # RingyDingy service identifier.  Use this to distinguish between
  # RingyDingys registering the same service.

  attr_reader :identifier

  ##
  # RingyDingy run loop thread.

  attr_reader :thread

  if $TESTING then
    attr_accessor :ring_finger, :renewer # :nodoc:
    attr_writer :ring_server, :thread # :nodoc:
  end

  ##
  # Lists of hosts to search for ring servers.  By default includes the subnet
  # broadcast address and localhost.

  BROADCAST_LIST = %w[<broadcast> localhost]

  ##
  # Finds the first live service matching +service_name+ on any ring server.
  # Ring servers are discovered via the +broadcast_list+.

  def self.find service_name, broadcast_list = BROADCAST_LIST
    DRb.start_service unless DRb.primary_server
    rf = Rinda::RingFinger.new broadcast_list

    services = {}

    rf.lookup_ring do |ts|
      services[ts.__drburi] = ts.read_all [:name, nil, DRbObject, nil]
    end

    services.each do |_, tuples|
      tuples.each do |_, found_service_name, service|
        begin
          next unless found_service_name == service_name

          service.method_missing :object_id # ping service for liveness

          return service
        rescue DRb::DRbConnError
          next
        rescue NoMethodError
          next
        end
      end
    end

    raise "unable to find service #{service_name.inspect}"
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
    ring_server.write [:name, @service, DRbObject.new(@object), @identifier],
                      @renewer
    return nil
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

  ##
  # Looks up the primary Rinde::RingServer.

  def ring_server
    return @ring_server unless @ring_server.nil?
    @ring_server = @ring_finger.lookup_ring_any
  end

  ##
  # Starts a thread that checks for a registration tuple every #check_every
  # seconds.

  def run
    @thread = Thread.start do
      loop do
        begin
          register unless registered?
        rescue DRb::DRbConnError
          @ring_server = nil
        rescue RuntimeError => e
          raise unless e.message == 'RingNotFound'
        end
        sleep @check_every
      end
    end

    self
  end

  ##
  # Stops checking for registration tuples.

  def stop
    @thread.kill
    return nil
  end

end

