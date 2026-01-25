defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /auth/salesforce/callback" do
    test "creates salesforce credential for authenticated user", %{conn: conn, user: user} do
      # Mock Ueberauth response
      auth_response = %Ueberauth.Auth{
        provider: :salesforce,
        info: %Ueberauth.Auth.Info{
          email: "user@salesforce.com"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "test_access_token",
          refresh_token: "test_refresh_token",
          expires_at: System.system_time(:second) + 3600
        },
        extra: %{
        raw_info: %{
          user: %{
            "user_id" => "0051t00000I7epAAB"
          }
        }
      }
      }

      conn =
        conn
        |> log_in_user(user)
        |> assign(:ueberauth_auth, auth_response)
        |> get("/auth/salesforce/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :info) == "Salesforce account connected successfully!"

      # Verify credential was created
      credential = SocialScribe.Accounts.get_user_salesforce_credential(user.id)
      assert credential.provider == "salesforce"
      assert credential.uid == "0051t00000I7epAAB"
      assert credential.token == "test_access_token"
      assert credential.refresh_token == "test_refresh_token"
      assert credential.email == "user@salesforce.com"
    end

    test "updates existing salesforce credential for authenticated user", %{conn: conn, user: user} do
      # Create initial credential
      _existing_credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "salesforce",
          uid: "0051t00000I7epAAB",
          token: "old_token",
          refresh_token: "old_refresh_token",
          email: "old@salesforce.com"
        })

      # Mock new auth response
      auth_response = %Ueberauth.Auth{
        provider: :salesforce,
        info: %Ueberauth.Auth.Info{
          email: "newemail@salesforce.com"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "new_access_token",
          refresh_token: "new_refresh_token",
          expires_at: System.system_time(:second) + 3600
        },
              extra: %{
        raw_info: %{
          user: %{
            "user_id" => "0051t00000I7epAAB"
          }
        }
      }
      }

      conn =
        conn
        |> log_in_user(user)
        |> assign(:ueberauth_auth, auth_response)
        |> get("/auth/salesforce/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"

      # Verify credential was updated
      credential = SocialScribe.Accounts.get_user_salesforce_credential(user.id)
      assert credential.token == "new_access_token"
      assert credential.refresh_token == "new_refresh_token"
      assert credential.email == "newemail@salesforce.com"
    end

    test "redirects with error when user not authenticated", %{conn: conn} do
      auth_response = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "0051t00000I7epAAB"
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth_response)
        |> get("/auth/salesforce/callback")

      assert redirected_to(conn, 302) == ~p"/users/log_in"
    end
  end
end
