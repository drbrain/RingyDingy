require 'minitest/autorun'
require 'ringy_dingy'

class TestRingyDingyLookup < MiniTest::Unit::TestCase

  def setup
    super

    @lookup = RingyDingy::Lookup.new []
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
      yield ts

      ro = DRbObject.new Object.new
      ts = Rinda::TupleSpace.new
      ts.write [:name, 'service', ro, 'the service']
      yield ts
    end

  end

end

