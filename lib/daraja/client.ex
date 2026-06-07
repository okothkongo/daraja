defmodule Daraja.Client do
  @moduledoc """
  Connection-level handle holding Daraja credentials, merchant defaults, and the
  target environment.

  Use `new/1` to build a client. Per-call options override values pulled from
  the `:daraja` application environment.

  ## Examples

  Build a client from application configuration:

      client = Daraja.Client.new()

  Override individual fields (handy for multi-tenant scenarios):

      client =
        Daraja.Client.new(
          consumer_key: merchant.consumer_key,
          consumer_secret: merchant.consumer_secret
        )

  Pass the client to an endpoint module:

      Daraja.Express.request(client, %{
        amount: 100,
        phone_number: "254712345678",
        account_reference: "Order-001"
      })

  ## Required vs. optional fields

  `consumer_key` and `consumer_secret` are always required. `new/1` raises if
  they are absent from both options and the application environment.

  `business_short_code`, `passkey`, and `callback_url` are STK Push-only and
  default to `nil`. `Daraja.Express.request/2` validates that they are set
  before sending a request.
  """

  @sandbox_url "https://sandbox.safaricom.co.ke"
  @production_url "https://api.safaricom.co.ke"

  @type env :: :sandbox | :production

  @type t :: %__MODULE__{
          consumer_key: String.t(),
          consumer_secret: String.t(),
          business_short_code: String.t() | nil,
          passkey: String.t() | nil,
          callback_url: String.t() | nil,
          environment: env()
        }

  defstruct [
    :consumer_key,
    :consumer_secret,
    :business_short_code,
    :passkey,
    :callback_url,
    environment: :sandbox
  ]

  @doc """
  Builds a `Daraja.Client` from options, falling back to the `:daraja`
  application environment for any missing value.

  Raises if `consumer_key` or `consumer_secret` cannot be resolved.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      consumer_key: opts[:consumer_key] || Daraja.Config.get!(:consumer_key),
      consumer_secret: opts[:consumer_secret] || Daraja.Config.get!(:consumer_secret),
      business_short_code:
        opts[:business_short_code] || Daraja.Config.get(:business_short_code, nil),
      passkey: opts[:passkey] || Daraja.Config.get(:passkey, nil),
      callback_url: opts[:callback_url] || Daraja.Config.get(:callback_url, nil),
      environment: opts[:environment] || Daraja.Config.get(:environment, :sandbox)
    }
  end

  @doc """
  Returns the Safaricom base URL for the client's `environment`.
  """
  @spec base_url(t()) :: String.t()
  def base_url(%__MODULE__{environment: :production}), do: @production_url
  def base_url(%__MODULE__{}), do: @sandbox_url
end

defimpl Inspect, for: Daraja.Client do
  import Inspect.Algebra

  @redacted "[REDACTED]"

  def inspect(client, opts) do
    fields = [
      consumer_key: client.consumer_key,
      consumer_secret: @redacted,
      business_short_code: client.business_short_code,
      passkey: redact(client.passkey),
      callback_url: client.callback_url,
      environment: client.environment
    ]

    concat(["#Daraja.Client<", to_doc(fields, opts), ">"])
  end

  defp redact(nil), do: nil
  defp redact(_), do: @redacted
end
