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
  # Finds the first live service matching +service_name+ on any ring server.
  # Ring servers are discovered via the +broadcast_list+.

  def find service_name
    found = each_tuple_space.find do |ts|
      tuples = ts.read_all [:name, nil, DRbObject, nil]

      tuples.find do |_, found_service_name, service|
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

    found
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
  # Waits until +service_name+ appears on any ring server.  Returns the first
  # service found with that name.
  #
  # If you launch a service via another process use this to wait until the
  # service comes up.

  def wait_for service_name
    queue   = Queue.new
    renewer = RingyDingy::CancelableRenewer.new

    each_tuple_space do |tuple_space|
      Thread.new do
        tuple = tuple_space.read [:name, service_name, DRbObject, nil], renewer
        queue.push tuple[2]
      end
    end

    service = queue.pop

    renewer.cancel

    service
  end

end

