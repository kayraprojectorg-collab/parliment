Rails.application.config.after_initialize do
  I18n.fallbacks.map(
    tr: %i[en],
    ru: %i[en],
    az: %i[tr en],
    tk: %i[tr en],
    kk: %i[ru en],
    ky: %i[ru en]
  )
end
