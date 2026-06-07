ExUnit.start()
Daraja.HTTPClient.Mock.start_link()

Application.put_env(:daraja, :warn_uncached_token, false)
Application.put_env(:daraja, :warn_tuple_security_credential, false)
