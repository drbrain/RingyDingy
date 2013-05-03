require 'rinda/tuplespace'

class RingyDingy::Lookup

  ##
  # The list of addresses where ring servers will be searched-for

  attr_reader :broadcast_list

  ##
  # The Rinda::RingFinger used to search for ring servers

  attr_reader :ring_finger

  ##
  # Lists of hosts to search for ring servers.  By default includes the subnet
  # broadcast address and localhost.

  def initialize broadcast_list = RingyDingy::BROADCAST_LIST
    DRb.start_service unless DRb.primary_server

    @broadcast_list = broadcast_list

    @ring_finger    = Rinda::RingFinger.new @broadcast_list
  end

  ##
  # Yields each tuple space found in the broadcast list

  def each_tuple_space
    return enum_for __method__ unless block_given?

    @ring_finger.lookup_ring do |tuple_space|
      yield tuple_space
    end
  end

  ##
  # Continually checks for tuple spaces and yields found tuple spaces.
  #
  # Returns a Thread that must be killed to shut down lookup:
  #
  #   def my_method
  #     thread = enumerate_tuple_spaces do |tuple_space|
  #       # ...
  #     end
  #   ensure
  #     thread.kill
  #   end

  def enumerate_tuple_spaces
    Thread.start do
      spaces = {}

      loop do
        @ring_finger.lookup_ring do |tuple_space|
          yield tuple_space
        end
      end
    end
  end

  ##
  # Finds the first live service matching +service_name+ on any ring server.
  # Ring servers are discovered via the +broadcast_list+.

  def find service_name
    found = nil

    each_tuple_space.any? do |ts|
      tuples = ts.read_all [:name, nil, DRbObject, nil]

      found = tuples.find do |_, found_service_name, service, _|
        begin
          next unless found_service_name == service_name

          if DRbObject === service then
            service.method_missing :object_id # ping service for liveness
          else
            service
          end
        rescue DRb::DRbConnError
          next
        rescue NoMethodError
          next
        end
      end
    end

    raise "unable to find service #{service_name.inspect}" unless found

    found[2]
  end

  ##
  # Waits until +service_name+ appears on any ring server.  Returns the first
  # service found with that name.
  #
  # If you launch a service via another process use this to wait until the
  # service comes up.

  def wait_for service_name
    queue   = Queue.new
    renewer = nil

    thread = enumerate_tuple_spaces do |tuple_space|
      renewer.cancel if renewer
      renewer = RingyDingy::CancelableRenewer.new

      Thread.new do
        template = [:name, service_name, DRbObject, nil]
        begin
          tuple = tuple_space.read template, renewer

          queue.push tuple[2]
        rescue DRb::DRbConnError => e
        end
      end
    end

    queue.pop
  ensure
    renewer.cancel
    thread.kill if thread
  end

end

