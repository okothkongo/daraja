defmodule Daraja.Express.Response do
  @moduledoc """
  Response structs for the STK Push API.
  """

  defmodule Success do
    @moduledoc "Returned when Safaricom successfully accepts the STK Push request."

    @type t :: %__MODULE__{
            merchant_request_id: String.t(),
            checkout_request_id: String.t(),
            response_code: String.t(),
            response_description: String.t(),
            customer_message: String.t()
          }

    defstruct [
      :merchant_request_id,
      :checkout_request_id,
      :response_code,
      :response_description,
      :customer_message
    ]
  end

  defmodule Error do
    @moduledoc "Returned when Safaricom rejects the STK Push request."

    @type t :: %__MODULE__{
            request_id: String.t(),
            error_code: String.t(),
            error_message: String.t()
          }

    defstruct [:request_id, :error_code, :error_message]
  end

  @spec from_map(map()) :: Success.t() | Error.t()
  def from_map(%{"CheckoutRequestID" => _} = map) do
    %Success{
      merchant_request_id: map["MerchantRequestID"],
      checkout_request_id: map["CheckoutRequestID"],
      response_code: map["ResponseCode"],
      response_description: map["ResponseDescription"],
      customer_message: map["CustomerMessage"]
    }
  end

  def from_map(map) do
    %Error{
      request_id: map["requestId"],
      error_code: map["errorCode"],
      error_message: map["errorMessage"]
    }
  end
end
