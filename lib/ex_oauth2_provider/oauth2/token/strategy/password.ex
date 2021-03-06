defmodule ExOauth2Provider.Token.Password do
  @moduledoc """
  Functions for dealing with refresh token strategy.
  """
  alias ExOauth2Provider.Utils.Error
  alias ExOauth2Provider.Token.Utils
  alias ExOauth2Provider.Token.Utils.Response
  alias ExOauth2Provider.Scopes

  @doc """
  Will grant access token by password authentication.

  ## Example
      ExOauth2Provider.Token.grant(%{
        "grant_type" => "password",
        "client_id" => "Jf5rM8hQBc",
        "client_secret" => "secret",
        "username" => "testuser@example.com",
        "password" => "secret"
      })
  ## Response
      {:ok, access_token}
      {:error, %{error: error, error_description: description}, http_status}
  """
  def grant(%{"grant_type" => "password"} = request) do
    %{request: request}
    |> get_password_auth_method(ExOauth2Provider.Config.password_auth)
    |> load_resource_owner
    |> Utils.load_client
    |> set_defaults
    |> validate_request
    |> issue_access_token
    |> Response.response
  end

  defp get_password_auth_method(params, {module, method}) do
    Map.merge(params, %{password_auth: {module, method}})
  end
  defp get_password_auth_method(params, _) do
    Error.add_error(params, Error.unsupported_grant_type())
  end

  defp load_resource_owner(%{error: _} = params), do: params
  defp load_resource_owner(%{password_auth: {module, method}, request: %{"username" => username, "password" => password}} = params) do
    case apply(module, method, [username, password]) do
      {:ok, resource_owner} -> Map.merge(params, %{resource_owner: resource_owner})
      {:error, reason}      -> Map.merge(params, %{error: :unauthorized, error_description: reason, error_http_status: :unauthorized})
    end
  end
  defp load_resource_owner(params), do: Error.add_error(params, Error.invalid_request())

  defp issue_access_token(%{error: _} = params), do: params
  defp issue_access_token(%{client: client, resource_owner: resource_owner, request: request} = params) do
    token_params = %{application: client,
                    scopes: request["scope"],
                    use_refresh_token: ExOauth2Provider.Config.use_refresh_token?}

    case Utils.find_or_create_access_token(resource_owner, token_params) do
      {:ok, access_token} -> Map.merge(params, %{access_token: access_token})
      {:error, error}     -> Error.add_error(params, error)
    end
  end

  defp set_defaults(%{error: _} = params), do: params
  defp set_defaults(%{request: request, client: client} = params) do
    scopes = params.request["scope"] || client.scopes

    request = request |> Map.merge(%{"scope" => scopes})

    params
    |> Map.merge(%{request: request})
  end

  defp validate_request(params) do
    params
    |> validate_scopes
  end

  defp validate_scopes(%{error: _} = params), do: params
  defp validate_scopes(%{request: %{"scope" => scopes}, client: client} = params) do
    scopes        = scopes |> Scopes.to_list
    server_scopes = client.scopes |> Scopes.to_list |> Scopes.default_to_server_scopes

    case Scopes.all?(server_scopes, scopes) do
      true -> params
      false -> Error.add_error(params, Error.invalid_scopes())
    end
  end
end
