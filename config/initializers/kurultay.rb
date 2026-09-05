# frozen_string_literal: true

# Kurultay white-label configuration.
# - Application name used in page titles, admin, system panel and e-mails.
# - Registers the custom side-menu icons (Decidim's icon helper only renders
#   icons registered here).
# - Renames the system panel wordmark from "Decidim" to "Kurultay".

Decidim.application_name = "Kurultay"

Rails.application.config.to_prepare do
  {
    "home-4-line" => "system",
    "user-line" => "system",
    "notification-3-line" => "system",
    "mail-line" => "system",
    "settings-3-line" => "system",
    "login-box-line" => "system"
  }.each do |name, category|
    next if Decidim.icons.all.key?(name)

    Decidim.icons.register(name:, icon: name, category:, description: "", engine: :core)
  end

  Decidim::System::ApplicationHelper.prepend(Module.new do
    def title = "Kurultay"
  end)

  # Default colors applied to organizations created from the system panel, so a
  # newly created tenant starts on the Kurultay palette instead of Decidim's.
  Decidim::System::CreateOrganization.prepend(Module.new do
    private

    def default_colors
      { primary: "#127C82", secondary: "#0A4A4E", tertiary: "#F2C14E" }
    end
  end)
end
