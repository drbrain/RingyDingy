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
  # Continually checks for tuple spaces and yields tuple spaces not previously
  # found.
  #
  # Returns a Thread that must be kill to shut down lookup.

  def enumerate_tuple_spaces
    Thread.start do
      Thread.current.abort_on_exception = true
      spaces = {}

      loop do
        @ring_finger.lookup_ring do |tuple_space|
          id = [tuple_space.__drburi, tuple_space.__drbref]

          next if spaces[id]

          spaces[id] = true

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
    renewer = RingyDingy::CancelableRenewer.new

    thread = enumerate_tuple_spaces do |tuple_space|
      Thread.new do
        tuple = [:name, service_name, DRbObject, nil]
        loop do
          begin
            tuple = tuple_space.read tuple, renewer
            queue.push tuple[2]
          rescue DRb::DRbConnError
            # HACK this may busy-loop forever depending on connection shutdown
          end
        end
      end
    end

    queue.pop
  ensure
    renewer.cancel
    thread.kill if thread
  end

end

