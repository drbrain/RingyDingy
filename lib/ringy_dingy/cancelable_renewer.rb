##
# This renewer can be canceled to shut down a TupleSpace operation.

class RingyDingy::CancelableRenewer
  include DRbUndumped

  ##
  # Creates a new renewer that will be checked every +sec+ for cancellation by
  # the TupleSpace

  def initialize seconds = 1
    @renew   = true
    @seconds = seconds
  end

  ##
  # Cancels the renewer

  def cancel
    @renew = false
  end

  def renew # :nodoc:
    @renew ? @seconds : true
  end

end

