require 'test/unit'

require 'ringy_dingy'

class StubRingFinger

  attr_accessor :ring_server

  def initialize
    @ring_server = nil
  end

  def lookup_ring_any
    raise RuntimeError, 'RingNotFound' if @ring_server.nil?
    @ring_server
  end

end

class StubRingServer

  attr_accessor :tuples

  def initialize
    @tuples = []
  end

  def write(*args)
    @tuples << args
  end

  def read_all(template)
    @tuples.map { |t,r| t }.select do |t|
      template[1].nil? or t[1] == template[1]
    end
  end

end

class Rinda::SimpleRenewer

  attr_reader :sec

  def ==(other)
    self.class === other and sec == other.sec
  end

end

class TestRingyDingy < Test::Unit::TestCase

  def setup
    @identifier = "#{Socket.gethostname.downcase}_#{$PID}"
    @object = ""
    @ringy_dingy = RingyDingy.new @object

    @stub_ring_server = StubRingServer.new
    @ringy_dingy.ring_server = @stub_ring_server
  end

  def test_class_find
    orig_ring_finger = Rinda::RingFinger
    ring_finger = Object.new

    Rinda.send :remove_const, :RingFinger
    Rinda.const_set :RingFinger, ring_finger

    def ring_finger.new broadcast_list
      @broadcast_list = broadcast_list
      self
    end

    def ring_finger.lookup_ring
      ts = StubRingServer.new
      def ts.__drburi() end

      service = Object.new
      def service.method_missing(*) end

      ts.write [:name, :service, service, nil], nil

      yield ts
    end

    RingyDingy.find :service

  ensure
    Rinda.send :remove_const, :RingFinger
    Rinda.const_set :RingFinger, orig_ring_finger
  end

  def test_initialize_broadcast_list
    service = RingyDingy.new @object, nil, 'blah', %w[192.0.2.1]

    assert_equal %w[192.0.2.1], service.ring_finger.broadcast_list
  end

  def test_initialize_lookup
    lookup = RingyDingy::Lookup.new %w[192.0.2.1]
    service = RingyDingy.new @object, nil, 'blah', lookup

    assert_same lookup.ring_finger, service.ring_finger
  end

  def test_initialize_ring_finger
    ring_finger = Rinda::RingFinger.new %w[192.0.2.1]
    service = RingyDingy.new @object, nil, 'blah', ring_finger

    assert_same ring_finger, service.ring_finger
  end

  def test_initialize_tuple_space
    tuple_space = Rinda::TupleSpace.new
    service = RingyDingy.new @object, nil, 'blah', tuple_space

    assert_nil               service.ring_finger
    assert_same tuple_space, service.ring_server
  end

  def test_identifier
    assert_equal @identifier, @ringy_dingy.identifier

    @ringy_dingy = RingyDingy.new @object, nil, 'blah'

    assert_equal "#{@identifier}_blah", @ringy_dingy.identifier
  end

  def test_register
    @ringy_dingy.register

    expected = [
      [[:name, :RingyDingy, DRbObject.new(@object), @identifier],
       Rinda::SimpleRenewer.new]
    ]

    assert_equal expected, @stub_ring_server.tuples
  end

  def test_register_service
    @ringy_dingy = RingyDingy.new @object, :MyDRbService
    @ringy_dingy.ring_server = @stub_ring_server
    @ringy_dingy.register

    expected = [
      [[:name, :MyDRbService, DRbObject.new(@object), @identifier],
       Rinda::SimpleRenewer.new]
    ]

    assert_equal expected, @stub_ring_server.tuples
  end

  def test_registered_eh
    @stub_ring_server.tuples << [
      [:name, :RingyDingy, @object, @identifier], nil]

    assert_equal true, @ringy_dingy.registered?
  end

  def test_registered_eh_not_registered
    assert_equal false, @ringy_dingy.registered?
  end

  def test_registered_eh_no_ring_server
    def @stub_ring_server.read_all(*args)
      raise DRb::DRbConnError
    end

    assert_equal false, @ringy_dingy.registered?

    assert_equal nil, @ringy_dingy.instance_variable_get(:@ring_server)
  end

  def test_registered_eh_service
    @ringy_dingy = RingyDingy.new @object, :MyDRbService
    @ringy_dingy.ring_server = @stub_ring_server

    @stub_ring_server.tuples << [
      [:name, :MyDRbService, @object, @identifier], nil]

    assert_equal true, @ringy_dingy.registered?
  end

  def test_renewer
    assert_equal Rinda::SimpleRenewer.new, @ringy_dingy.renewer
  end

  def test_ring_server
    util_create_stub_ring_finger :server

    assert_equal :server, @ringy_dingy.ring_server
  end

  def test_ring_server_not_found
    util_create_stub_ring_finger

    assert_raise RuntimeError do @ringy_dingy.ring_server end
  end

  def test_stop
    @ringy_dingy.thread = Thread.start do sleep end
    assert_equal nil, @ringy_dingy.stop
  end

  def util_create_stub_ring_finger(rs = nil)
    @ringy_dingy.ring_server = nil

    ring_finger = StubRingFinger.new

    ring_finger.ring_server = rs unless rs.nil?

    @ringy_dingy.ring_finger = ring_finger
  end

end

