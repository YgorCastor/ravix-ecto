defmodule Ecto.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :ravix_ecto,
    read_only: false,
    adapter: Ravix.Ecto.Adapter

  def uuid do
    Ecto.UUID
  end
end
