require 'minitest/autorun'
require 'ringy_dingy'

class TestRingyDingyLookup < MiniTest::Unit::TestCase

  def setup
    super

    @lookup = RingyDingy::Lookup.new []
  end

  def test_enumerate_tuple_spaces
    stub_ring_finger

    items = []

    thread = @lookup.enumerate_tuple_spaces do |ts|
      items << ts
    end

    Thread.pass while items.empty?

    refute_empty items
  ensure
    thread.kill if thread
  end

  def test_find
    stub_ring_finger

    found = @lookup.find 'service'

    assert_kind_of Object, found
  end

  def test_wait_for
    stub_ring_finger

    found = @lookup.wait_for 'service'

    assert_kind_of Object, found
  end

  def stub_ring_finger
    def (@lookup.ring_finger).lookup_ring
      ts = Rinda::TupleSpace.new
      yield DRb::DRbObject.new ts

      ro = DRbObject.new Object.new
      ts = Rinda::TupleSpace.new
      ts.write [:name, 'service', ro, 'the service']
      yield DRb::DRbObject.new ts
    end
  end

end

