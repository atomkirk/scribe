defmodule SocialScribeWeb.Router do
  use SocialScribeWeb, :router

  import Oban.Web.Router
  import SocialScribeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SocialScribeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SocialScribeWeb do
    pipe_through :browser
  end

  # Other scopes may use custom stacks.
  # scope "/api", SocialScribeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:social_scribe, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SocialScribeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  ## Authentication routes

  scope "/auth", SocialScribeWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", SocialScribeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    post "/users/log_in", UserSessionController, :create
  end

  scope "/dashboard", SocialScribeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {SocialScribeWeb.UserAuth, :ensure_authenticated},
        {SocialScribeWeb.LiveHooks, :assign_current_path}
      ],
      layout: {SocialScribeWeb.Layouts, :dashboard} do
      live "/", HomeLive

      live "/settings", UserSettingsLive, :index
      live "/settings/facebook_pages", UserSettingsLive, :facebook_pages

      live "/meetings", MeetingLive.Index, :index
      live "/meetings/:id", MeetingLive.Show, :show
      live "/meetings/:id/draft_post/:automation_result_id", MeetingLive.Show, :draft_post
      live "/meetings/:id/hubspot", MeetingLive.Show, :hubspot
      live "/meetings/:id/salesforce", MeetingLive.Show, :salesforce

      live "/automations", AutomationLive.Index, :index
      live "/automations/new", AutomationLive.Index, :new
      live "/automations/:id/edit", AutomationLive.Index, :edit

      live "/automations/:id", AutomationLive.Show, :show
      live "/automations/:id/show/edit", AutomationLive.Show, :edit
    end
  end

  scope "/", SocialScribeWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{SocialScribeWeb.UserAuth, :mount_current_user}] do
      live "/", LandingLive
    end
  end
end
