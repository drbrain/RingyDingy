require 'minitest/autorun'

class TestRingyDingyCancelableRenewer < MiniTest::Unit::TestCase

  def setup
    super

    @renewer = RingyDingy::CancelableRenewer.new
  end

  def test_cancel
    @renewer.cancel

    assert_equal true, @renewer.renew
  end

  def test_marshal_dump
    assert_raises TypeError do
      Marshal.dump @renewer
    end
  end

  def test_renew
    assert_equal 1, @renewer.renew

    @renewer.cancel

    assert_equal true, @renewer.renew
  end

  def test_renew_seconds
    @renewer = RingyDingy::CancelableRenewer.new 2

    assert_equal 2, @renewer.renew
  end

end

