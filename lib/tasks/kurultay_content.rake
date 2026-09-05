# frozen_string_literal: true

# Idempotent, comprehensive real content for the Kurultay platform.
# Run with: bin/rails kurultay:seed_content
#
# Safe to run repeatedly: records are matched by natural keys and updated in
# place. Does NOT touch theme files. Optional components are seeded only when
# their gem is installed, and each feature is wrapped so one failure never
# blocks the rest.
#
# Covers: Organization + welcome, Participants, Taxonomy, Static pages,
# Assemblies, Processes, per-space homepage content blocks + hero images,
# Proposals (with states + follows), Meetings, Comments, Debates, Blog posts,
# Pages, Budgets + Projects, Accountability statuses + Results, Surveys.

namespace :kurultay do
  desc "Seed the real Kurultay content (bilingual en/tr, idempotent)"
  task seed_content: :environment do
    KurultaySeed.new.call
  end
end

class KurultaySeed
  def call
    @organization = Decidim::Organization.first
    abort("No organization found. Create it first at /system, then re-run.") unless @organization

    configure_organization!
    seed_participants!
    seed_taxonomy!
    seed_static_pages!
    seed_assemblies!
    seed_processes!

    puts "✔ Kurultay content seeded for organization ##{@organization.id}."
  end

  private

  attr_reader :organization

  def t(en, tr) = { "en" => en, "tr" => tr }
  def para(en, tr) = t("<p>#{en}</p>", "<p>#{tr}</p>")
  def para_multi(en_arr, tr_arr) = t(en_arr.map { |x| "<p>#{x}</p>" }.join, tr_arr.map { |x| "<p>#{x}</p>" }.join)

  def rich_proposal_body(p_en, p_tr, title_en, title_tr)
    para_multi(
      ["<strong>Problem.</strong> #{p_en} requires coordinated action across the Turkic states, which today lack a shared framework.",
       "<strong>Proposal.</strong> Establish a joint working group and a funded pilot under the #{title_en} process, with clear milestones and public reporting.",
       "<strong>Expected outcome.</strong> A concrete, measurable result that member delegations can adopt and track together."],
      ["<strong>Sorun.</strong> #{p_tr}, bugün ortak bir çerçeveden yoksun olan Türk devletleri arasında eşgüdümlü eylem gerektirir.",
       "<strong>Öneri.</strong> #{title_tr} süreci kapsamında net kilometre taşları ve kamuya açık raporlama ile ortak bir çalışma grubu ve finanse edilen bir pilot kurmak.",
       "<strong>Beklenen sonuç.</strong> Üye heyetlerin birlikte benimseyip izleyebileceği somut ve ölçülebilir bir sonuç."]
    )
  end

  def safely(label)
    yield
  rescue StandardError => e
    warn "  ⚠ #{label}: #{e.class}: #{e.message}"
  end

  def component_available?(name)
    Decidim.component_registry.manifests.map { |m| m.name.to_s }.include?(name.to_s)
  end

  def admin_user
    @admin_user ||= Decidim::User.where(organization:, admin: true).first || @participants&.first
  end

  # ---- Organization ----------------------------------------------------

  def configure_organization!
    supported = %w(en tr) & Decidim.available_locales.map(&:to_s)
    locales = (Array(organization.available_locales).map(&:to_s) | supported).presence
    organization.available_locales = locales if locales
    organization.default_locale = "tr" if supported.include?("tr")

    organization.name = t("Kurultay", "Kurultay")
    organization.description = para(
      "Kurultay is the digital parliament of the Turkic world — a cross-border civic space where " \
      "civil-society organisations from the Turkic states deliberate, propose and decide together.",
      "Kurultay, Türk dünyasının dijital parlamentosudur — Türk devletlerinin sivil toplum " \
      "kuruluşlarının ortak meseleleri birlikte müzakere ettiği, önerdiği ve karara bağladığı sınır ötesi bir sivil alandır."
    )
    organization.save!
    seed_welcome_text!
  end

  def seed_welcome_text!
    if Decidim::ContentBlock.where(organization:, scope_name: :homepage).none?
      Decidim::ContentBlocksCreator.new(organization).create_default!
    end
    hero = Decidim::ContentBlock.find_by(organization:, manifest_name: :hero, scope_name: :homepage)
    return unless hero

    hero.settings = (hero.read_attribute(:settings) || {}).merge(
      "welcome_text_en" => "Welcome to Kurultay — the common assembly of the Turkic world.",
      "welcome_text_tr" => "Kurultay'a hoş geldiniz — Türk dünyasının ortak meclisi."
    )
    hero.save!
  end

  # ---- Participants ----------------------------------------------------

  PARTICIPANTS = [
    ["Aylin Demir", "aylin.demir@kurultay.example", "aylindemir"],
    ["Elnur Mammadov", "elnur.mammadov@kurultay.example", "elnurmammadov"],
    ["Aigerim Nurlan", "aigerim.nurlan@kurultay.example", "aigerimnurlan"],
    ["Nurlan Bekov", "nurlan.bekov@kurultay.example", "nurlanbekov"],
    ["Maral Rejepova", "maral.rejepova@kurultay.example", "maralrejepova"],
    ["Dilnoza Karimova", "dilnoza.karimova@kurultay.example", "dilnozakarimova"],
    ["Kanat Toktogulov", "kanat.toktogulov@kurultay.example", "kanattoktogulov"],
    ["Leyla Hüseynova", "leyla.huseynova@kurultay.example", "leylahuseynova"]
  ].freeze

  def seed_participants!
    @participants = PARTICIPANTS.map do |name, email, nickname|
      user = Decidim::User.find_or_initialize_by(email:, organization:)
      user.name = name
      user.nickname = nickname if user.nickname.blank?
      if user.new_record?
        user.password = "Deniz!Kule742026"
        user.password_confirmation = "Deniz!Kule742026"
      end
      user.tos_agreement = true
      user.accepted_tos_version = organization.tos_version
      user.confirmed_at ||= Time.current
      user.locale ||= organization.default_locale
      user.save!
      user
    end
  end

  def participant(index) = @participants[index % @participants.size]

  # ---- Taxonomy --------------------------------------------------------

  TERMS = [
    ["Culture", "Kültür"], ["Economy", "Ekonomi"], ["Education", "Eğitim"],
    ["Environment", "Çevre"], ["Youth", "Gençlik"], ["Diplomacy", "Diplomasi"]
  ].freeze

  def seed_taxonomy!
    @root = organization.taxonomies.roots.detect { |x| x.name["en"] == "Policy Areas" } ||
            Decidim::Taxonomy.create!(name: t("Policy Areas", "Politika Alanları"), organization:, parent: nil)

    @terms = TERMS.to_h do |en, tr|
      term = @root.children.reload.detect { |c| c.name["en"] == en } ||
             Decidim::Taxonomy.create!(name: t(en, tr), organization:, parent: @root)
      [en, term]
    end

    return if @root.taxonomy_filters.any?

    Decidim::TaxonomyFilter.create!(
      root_taxonomy: @root,
      participatory_space_manifests: [:assemblies, :participatory_processes],
      filter_items: @terms.values.map { |term| Decidim::TaxonomyFilterItem.new(taxonomy_item: term) }
    )
  end

  def assign_taxonomy(resource, term_name)
    Decidim::Taxonomization.find_or_create_by!(taxonomy: @terms[term_name], taxonomizable: resource)
  end

  # ---- Static pages ----------------------------------------------------

  def seed_static_pages!
    [
      ["about", t("About us", "Hakkımızda"),
       para("Kurultay brings together civil-society organisations across the Turkic world to build shared policy through open deliberation.",
            "Kurultay, Türk dünyası genelindeki sivil toplum kuruluşlarını açık müzakere yoluyla ortak politika üretmek için bir araya getirir.")],
      ["how-it-works", t("How it works", "Nasıl çalışır"),
       para("Members submit proposals, debate them in meetings, and reach shared recommendations through transparent decision-making.",
            "Üyeler öneriler sunar, bunları toplantılarda tartışır ve şeffaf karar alma yoluyla ortak tavsiyelere ulaşır.")],
      ["faq", t("Frequently asked questions", "Sıkça sorulan sorular"),
       para("Answers to common questions about membership, participation and decisions on Kurultay.",
            "Üyelik, katılım ve Kurultay'daki kararlar hakkında sık sorulan soruların yanıtları.")],
      ["contact", t("Contact", "İletişim"),
       para("Reach the Kurultay secretariat for institutional enquiries and partnership requests.",
            "Kurumsal sorular ve iş birliği talepleri için Kurultay sekretaryası ile iletişime geçin.")]
    ].each do |slug, title, content|
      page = Decidim::StaticPage.find_or_initialize_by(organization:, slug:)
      page.title = title
      page.content = content
      page.save!
    end
  end

  # ---- Assemblies ------------------------------------------------------

  COUNTRIES = [
    ["turkey", "Turkey", "Türkiye", "Diplomacy"],
    ["azerbaijan", "Azerbaijan", "Azerbaycan", "Economy"],
    ["kazakhstan", "Kazakhstan", "Kazakistan", "Education"],
    ["kyrgyzstan", "Kyrgyzstan", "Kırgızistan", "Youth"],
    ["turkmenistan", "Turkmenistan", "Türkmenistan", "Environment"],
    ["uzbekistan", "Uzbekistan", "Özbekistan", "Culture"]
  ].freeze

  def seed_assemblies!
    COUNTRIES.each_with_index do |(slug, en, tr, term), i|
      assembly = upsert_assembly(slug, en, tr)
      assign_taxonomy(assembly, term)
      safely("assembly homepage #{slug}") { seed_space_homepage!(assembly, "The #{en} delegation to Kurultay.", "#{tr} heyeti.") }

      proposals = upsert_component(assembly, "proposals", t("Proposals", "Öneriler"))
      safely("proposal states #{slug}") { ensure_proposal_states(proposals) }
      meetings = upsert_component(assembly, "meetings", t("Meetings", "Toplantılar"))

      p1 = upsert_proposal(proposals, t("#{en} youth exchange programme", "#{tr} gençlik değişim programı"),
                           para("A yearly exchange bringing young delegates from #{en} into the shared agenda.",
                                "#{tr} kaynaklı genç delegeleri ortak gündeme taşıyan yıllık bir değişim programı."), participant(i))
      assign_taxonomy(p1, term)
      safely("answer #{slug}") { answer_proposal(p1, :accepted) }
      follow!(p1, participant(i + 1)); follow!(p1, participant(i + 2))
      add_comments(p1, [[participant(i + 1), "This aligns with our national priorities.", "Bu, ulusal önceliklerimizle uyumludur."],
                        [participant(i + 3), "We support a shared budget for it.", "Bunun için ortak bir bütçeyi destekliyoruz."]])

      p2 = upsert_proposal(proposals, t("#{en} language and heritage grants", "#{tr} dil ve miras hibeleri"),
                           para("A national grant line for language schools and heritage projects in #{en}.",
                                "#{tr} genelinde dil okullarını ve miras projelerini destekleyen ulusal hibe hattı."), participant(i + 1))
      assign_taxonomy(p2, term)
      safely("answer2 #{slug}") { answer_proposal(p2, :evaluating) }

      m = upsert_meeting(meetings, t("#{en} delegation meeting", "#{tr} heyet toplantısı"),
                         para("Working session of the #{en} delegation.", "#{tr} heyetinin çalışma oturumu."))
      assign_taxonomy(m, term)

      safely("assembly pages #{slug}") do
        add_page(assembly, t("Mandate", "Görev tanımı"),
                 para("The mandate and working rules of the #{en} delegation within Kurultay.",
                      "#{tr} heyetinin Kurultay içindeki görev tanımı ve çalışma kuralları."))
      end
      safely("assembly debate #{slug}") do
        add_debate(assembly, term, t("Priorities of the #{en} delegation", "#{tr} heyetinin öncelikleri"),
                   para("An open debate on this delegation's priorities for the coming year.",
                        "Bu heyetin önümüzdeki yıla dair öncelikleri üzerine açık bir tartışma."))
      end
    end
  end

  def upsert_assembly(slug, en, tr)
    assembly = Decidim::Assembly.find_or_initialize_by(organization:, slug:)
    assembly.title = t("#{en} Assembly", "#{tr} Meclisi")
    assembly.subtitle = t("National delegation to Kurultay", "Kurultay ulusal heyeti")
    assembly.short_description = para("The national assembly channelling #{en}'s civil society into the shared agenda.",
                                      "#{tr} sivil toplumunu ortak gündeme taşıyan ulusal meclis.")
    assembly.description = para("This assembly gathers proposals, meetings and decisions from #{en}.",
                                "Bu meclis, #{tr} kaynaklı önerileri, toplantıları ve kararları toplar.")
    assembly.published_at ||= Time.current
    assembly.save!
    assembly
  end

  # ---- Processes -------------------------------------------------------

  PROCESSES = [
    ["cultural-heritage", "Shared Cultural Heritage", "Ortak Kültürel Miras", "Culture",
     [["Digital archive of Turkic manuscripts", "Türk el yazmalarının dijital arşivi"],
      ["Shared calendar of cultural festivals", "Ortak kültürel festival takvimi"],
      ["Joint conservation of historic sites", "Tarihi mekânların ortak korunması"]]],
    ["green-steppe", "Green Steppe Initiative", "Yeşil Bozkır Girişimi", "Environment",
     [["Cross-border steppe restoration fund", "Sınır ötesi bozkır restorasyon fonu"],
      ["Shared water-basin monitoring network", "Ortak su havzası izleme ağı"],
      ["Renewable energy cooperation pact", "Yenilenebilir enerji iş birliği paktı"]]],
    ["economic-cooperation", "Economic Cooperation", "Ekonomik İş Birliği", "Economy",
     [["Unified trade-corridor standards", "Birleşik ticaret koridoru standartları"],
      ["Joint SME investment platform", "Ortak KOBİ yatırım platformu"],
      ["Common digital-payments framework", "Ortak dijital ödeme çerçevesi"]]]
  ].freeze

  def seed_processes!
    group = safely("process group") { seed_process_group! }
    PROCESSES.each_with_index do |(slug, title_en, title_tr, term, proposal_titles), i|
      process = upsert_process(slug, title_en, title_tr, group)
      assign_taxonomy(process, term)
      safely("process homepage #{slug}") { seed_space_homepage!(process, "The #{title_en} process.", "#{title_tr} süreci.") }

      proposals = upsert_component(process, "proposals", t("Proposals", "Öneriler"))
      safely("proposal states #{slug}") { ensure_proposal_states(proposals) }
      meetings = upsert_component(process, "meetings", t("Meetings", "Toplantılar"))

      proposal_titles.each_with_index do |(p_en, p_tr), j|
        proposal = upsert_proposal(proposals, t(p_en, p_tr),
                                   rich_proposal_body(p_en, p_tr, title_en, title_tr),
                                   participant(i + j))
        assign_taxonomy(proposal, term)
        follow!(proposal, participant(i + j + 1))
        safely("answer #{slug}-#{j}") { answer_proposal(proposal, %i(accepted evaluating rejected)[j % 3]) }
        add_comments(proposal, [[participant(i + j + 1), "A well-scoped proposal; we back it.", "İyi tanımlanmış bir öneri; destekliyoruz."],
                                [participant(i + j + 3), "Please add a monitoring indicator.", "Lütfen bir izleme göstergesi ekleyin."]])
      end

      [t("#{title_en} working session", "#{title_tr} çalışma oturumu"),
       t("#{title_en} public hearing", "#{title_tr} kamuoyu dinleme oturumu")].each do |m_title|
        m = upsert_meeting(meetings, m_title, para("Open session of the #{title_en} process.", "#{title_tr} sürecinin açık oturumu."))
        assign_taxonomy(m, term)
      end

      safely("debates #{slug}") do
        add_debate(process, term, t("Open debate: #{title_en}", "Açık tartışma: #{title_tr}"),
                   para("Share your views on the direction of the #{title_en} process.", "#{title_tr} sürecinin yönü hakkında görüşlerinizi paylaşın."))
        add_debate(process, term, t("Priorities for next year", "Gelecek yılın öncelikleri"),
                   para("Which priorities should this process focus on next year?", "Bu süreç gelecek yıl hangi önceliklere odaklanmalı?"))
      end

      safely("blog #{slug}") do
        add_blog(process, [
                   [t("#{title_en}: first working session held", "#{title_tr}: ilk çalışma oturumu yapıldı"),
                    para("Delegates from all member states met to open the #{title_en} process.", "Tüm üye devletlerden delegeler #{title_tr} sürecini açmak için bir araya geldi.")],
                   [t("Call for proposals now open", "Öneri çağrısı başladı"),
                    para("Civil-society organisations can now submit proposals to the #{title_en} process.", "Sivil toplum kuruluşları artık #{title_tr} sürecine öneri sunabilir.")]
                 ])
      end

      safely("budget #{slug}") do
        add_budget(process, t("#{title_en} participatory budget", "#{title_tr} katılımcı bütçesi"),
                   para("Allocate the shared fund of the #{title_en} process across projects.", "#{title_tr} sürecinin ortak fonunu projelere ayırın."),
                   [[t("Pilot programme", "Pilot program"), 250_000],
                    [t("Capacity building", "Kapasite geliştirme"), 400_000],
                    [t("Regional grants", "Bölgesel hibeler"), 600_000]])
      end

      safely("accountability #{slug}") do
        add_accountability(process, term, [
                             [t("Phase 1 delivered", "Birinci aşama tamamlandı"), 100],
                             [t("Phase 2 in progress", "İkinci aşama devam ediyor"), 45],
                             [t("Phase 3 planned", "Üçüncü aşama planlandı"), 5]
                           ])
      end

      safely("survey #{slug}") do
        add_survey(process, t("#{title_en} priorities survey", "#{title_tr} öncelik anketi"), [
                     [t("What is your organisation's top priority?", "Kuruluşunuzun en önemli önceliği nedir?"), "short_response"],
                     [t("Describe the outcome you expect.", "Beklediğiniz sonucu açıklayın."), "long_response"]
                   ])
      end
    end
  end

  def upsert_process(slug, title_en, title_tr, group = nil)
    process = Decidim::ParticipatoryProcess.find_or_initialize_by(organization:, slug:)
    process.title = t(title_en, title_tr)
    process.subtitle = t("A shared process of the Turkic world parliament", "Türk dünyası parlamentosunun ortak süreci")
    process.short_description = para(
      "An open, cross-border process where civil-society delegations from the Turkic states shape common policy on #{title_en.downcase}.",
      "Türk devletlerinin sivil toplum heyetlerinin #{title_tr.downcase} konusunda ortak politika şekillendirdiği açık ve sınır ötesi bir süreç."
    )
    process.description = rich_process_description(title_en, title_tr)
    process.participatory_process_group = group if group
    process.promoted = true
    process.published_at ||= Time.current
    process.start_date ||= Date.current
    process.end_date ||= 6.months.from_now.to_date
    process.save!
    safely("process steps #{slug}") { seed_process_steps!(process) }
    process
  end

  def rich_process_description(title_en, title_tr)
    t(
      "<h3>About this process</h3>" \
      "<p>The #{title_en} process brings together civil-society organisations from Türkiye, Azerbaijan, Kazakhstan, " \
      "Kyrgyzstan, Turkmenistan and Uzbekistan to deliberate and agree shared action on #{title_en.downcase}.</p>" \
      "<h3>Objectives</h3><ul>" \
      "<li>Build a common position across the Turkic world.</li>" \
      "<li>Turn citizen and organisation proposals into concrete recommendations.</li>" \
      "<li>Track delivery transparently through public meetings and published results.</li></ul>" \
      "<h3>How to take part</h3>" \
      "<p>Submit a proposal, join a meeting, comment on others' ideas, or endorse the proposals you support. " \
      "Every phase of this process is public.</p>",
      "<h3>Bu süreç hakkında</h3>" \
      "<p>#{title_tr} süreci; Türkiye, Azerbaycan, Kazakistan, Kırgızistan, Türkmenistan ve Özbekistan sivil toplum " \
      "kuruluşlarını #{title_tr.downcase} konusunda ortak eylemde bir araya getirir.</p>" \
      "<h3>Amaçlar</h3><ul>" \
      "<li>Türk dünyası genelinde ortak bir tutum oluşturmak.</li>" \
      "<li>Yurttaş ve kuruluş önerilerini somut tavsiyelere dönüştürmek.</li>" \
      "<li>Kamuya açık toplantılar ve yayımlanan sonuçlarla teslimatı şeffaf izlemek.</li></ul>" \
      "<h3>Nasıl katılırsınız</h3>" \
      "<p>Bir öneri sunun, toplantıya katılın, başkalarının fikirlerine yorum yapın veya desteklediğiniz önerileri " \
      "onaylayın. Bu sürecin her aşaması kamuya açıktır.</p>"
    )
  end

  PROCESS_STEPS = [
    ["Diagnosis", "Teşhis", "Gathering issues and evidence from all delegations.", "Tüm heyetlerden konu ve kanıt toplama."],
    ["Deliberation", "Müzakere", "Proposals, debates and public meetings.", "Öneriler, tartışmalar ve kamuya açık toplantılar."],
    ["Decision", "Karar", "Voting and shared recommendations.", "Oylama ve ortak tavsiyeler."]
  ].freeze

  def seed_process_steps!(process)
    PROCESS_STEPS.each_with_index do |(s_en, s_tr, d_en, d_tr), i|
      step = process.steps.reload.detect { |s| s.title["en"] == s_en } ||
             Decidim::ParticipatoryProcessStep.new(participatory_process: process)
      step.title = t(s_en, s_tr)
      step.description = para(d_en, d_tr)
      step.position = i
      step.active = i.zero?
      step.start_date ||= (Date.current >> (i - 1))
      step.end_date ||= (Date.current >> (i + 1))
      step.save!
    end
  end

  def seed_process_group!
    group = Decidim::ParticipatoryProcessGroup.where(organization:).detect { |g| g.title["en"] == "Turkic World Processes" } ||
            Decidim::ParticipatoryProcessGroup.new(organization:)
    group.title = t("Turkic World Processes", "Türk Dünyası Süreçleri")
    group.description = para(
      "The thematic processes through which the Turkic world parliament builds shared policy across culture, " \
      "environment and the economy.",
      "Türk dünyası parlamentosunun kültür, çevre ve ekonomi alanlarında ortak politika ürettiği tematik süreçler."
    )
    group.save!
    Decidim::ContentBlocksCreator.new(group).create_default!
    group
  end

  # ---- Per-space homepage ----------------------------------------------

  def seed_space_homepage!(space, desc_en, desc_tr)
    Decidim::ContentBlocksCreator.new(space).create_default!
    scope = space.manifest.content_blocks_scope_name

    html = Decidim::ContentBlock.find_or_initialize_by(
      decidim_organization_id: organization.id, scope_name: scope, scoped_resource_id: space.id, manifest_name: :html
    )
    html.settings = (html.read_attribute(:settings) || {}).merge("html_content_en" => "<p>#{desc_en}</p>", "html_content_tr" => "<p>#{desc_tr}</p>")
    html.weight ||= 15
    html.published_at ||= Time.current
    html.save!

    hero = Decidim::ContentBlock.find_by(
      decidim_organization_id: organization.id, scope_name: scope, scoped_resource_id: space.id, manifest_name: :hero
    )
    attach_hero_image!(space, hero)
  end

  def attach_hero_image!(space, hero_block)
    bytes = hero_png_bytes
    return unless bytes

    space.hero_image.attach(io: StringIO.new(bytes), filename: "hero.png", content_type: "image/png") unless space.hero_image.attached?
    if hero_block && !hero_block.images_container.background_image.attached?
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "hero.png", content_type: "image/png")
      hero_block.images_container.background_image = blob
      hero_block.save!
    end
  rescue StandardError => e
    warn "  ⚠ hero image skipped for #{space.slug}: #{e.message}"
  end

  def hero_png_bytes
    return @hero_png_bytes if defined?(@hero_png_bytes)

    path = Rails.root.join("tmp", "kurultay_hero.png").to_s
    cmd = if system("command -v convert > /dev/null 2>&1") then "convert -size 1600x600 gradient:#0A4A4E-#127C82 #{path}"
          elsif system("command -v magick > /dev/null 2>&1") then "magick -size 1600x600 gradient:#0A4A4E-#127C82 #{path}"
          end
    @hero_png_bytes = if cmd && system(cmd) && File.exist?(path)
                        File.binread(path)
                      else
                        warn "  ⚠ ImageMagick not found; skipping hero images (SCSS fallback still shows a dark hero)."
                        nil
                      end
  end

  # ---- Components & resources ------------------------------------------

  def upsert_component(space, manifest, name, settings: {})
    component = space.components.find_by(manifest_name: manifest) ||
                Decidim::Component.new(manifest_name: manifest, participatory_space: space)
    component.name = name
    component.settings = settings if settings.present?
    component.published_at ||= Time.current
    component.save!
    component
  end

  def upsert_proposal(component, title, body, author)
    existing = Decidim::Proposals::Proposal.where(component:).detect { |p| p.title["en"] == title["en"] }
    return existing if existing

    proposal = Decidim::Proposals::Proposal.new(component:, title:, body:, published_at: Time.current)
    proposal.add_coauthor(author)
    proposal.save!
    proposal
  end

  def ensure_proposal_states(component)
    return if Decidim::Proposals::ProposalState.where(component:).any?

    Decidim::Proposals.create_default_states!(component, admin_user, with_traceability: false)
  end

  def answer_proposal(proposal, token)
    state = Decidim::Proposals::ProposalState.where(component: proposal.component, token:).first
    return unless state

    proposal.update!(proposal_state: state, answered_at: Time.current, state_published_at: Time.current)
  end

  def follow!(followable, user)
    Decidim::Follow.find_or_create_by!(followable:, user:)
  rescue StandardError => e
    warn "  ⚠ follow skipped: #{e.message}"
  end

  def upsert_meeting(component, title, description)
    existing = Decidim::Meetings::Meeting.where(component:).detect { |m| m.title["en"] == title["en"] }
    return existing if existing

    Decidim::Meetings::Meeting.create!(
      component:, title:, description:, author: organization,
      type_of_meeting: "in_person", registration_type: "registration_disabled",
      registrations_enabled: false, available_slots: 0,
      start_time: 1.week.from_now, end_time: 1.week.from_now + 2.hours,
      address: "Kurultay Secretariat", location: t("Kurultay Secretariat", "Kurultay Sekretaryası"),
      latitude: 41.0082, longitude: 28.9784, published_at: Time.current
    )
  end

  def add_comments(proposal, entries)
    return if proposal.comments.any?

    entries.each do |author, en, tr|
      Decidim::Comments::Comment.create!(commentable: proposal, root_commentable: proposal, author:, body: t(en, tr), depth: 0, alignment: 0)
    end
    proposal.update_comments_count
  end

  # ---- Optional components (only when the gem is installed) -------------

  def add_page(space, name, body)
    return unless component_available?(:pages)

    component = upsert_component(space, "pages", name)
    page = Decidim::Pages::Page.find_or_initialize_by(component:)
    page.body = body
    page.save!
  end

  def add_debate(space, term, title, description)
    return unless component_available?(:debates)

    component = space.components.find_by(manifest_name: "debates") ||
                upsert_component(space, "debates", t("Debates", "Tartışmalar"))
    debate = Decidim::Debates::Debate.where(component:).detect { |d| d.title["en"] == title["en"] } ||
             Decidim::Debates::Debate.create!(component:, title:, description:,
                                              instructions: para("Be respectful and constructive.", "Saygılı ve yapıcı olun."),
                                              author: organization)
    assign_taxonomy(debate, term)
  end

  def add_blog(space, posts)
    return unless component_available?(:blogs)

    component = upsert_component(space, "blogs", t("News", "Haberler"))
    posts.each do |title, body|
      next if Decidim::Blogs::Post.where(component:).detect { |p| p.title["en"] == title["en"] }

      Decidim::Blogs::Post.create!(component:, title:, body:, author: organization, published_at: Time.current)
    end
  end

  def add_budget(space, name, description, projects)
    return unless component_available?(:budgets)

    component = upsert_component(space, "budgets", name)
    budget = Decidim::Budgets::Budget.where(component:).first ||
             Decidim::Budgets::Budget.create!(component:, title: name, description:, total_budget: 1_250_000)
    projects.each do |p_title, amount|
      next if Decidim::Budgets::Project.where(budget:).detect { |pr| pr.title["en"] == p_title["en"] }

      Decidim::Budgets::Project.create!(budget:, title: p_title,
                                        description: para("A funded project within this participatory budget.", "Bu katılımcı bütçe içinde finanse edilen bir proje."),
                                        budget_amount: amount)
    end
  end

  def add_accountability(space, term, results)
    return unless component_available?(:accountability)

    component = upsert_component(space, "accountability", t("Results", "Sonuçlar"))
    if Decidim::Accountability::Status.where(component:).none?
      [["ongoing", t("Ongoing", "Devam ediyor")], ["completed", t("Completed", "Tamamlandı")], ["planned", t("Planned", "Planlandı")]].each do |key, name|
        Decidim::Accountability::Status.create!(component:, key:, name:)
      end
    end
    results.each do |title, progress|
      next if Decidim::Accountability::Result.where(component:).detect { |r| r.title["en"] == title["en"] }

      result = Decidim::Accountability::Result.new(component:, title:,
                                                   description: para("A tracked result of the process.", "Sürecin izlenen bir sonucu."),
                                                   progress:, taxonomies: [@terms[term]])
      result.save!(validate: false)
    end
  end

  def add_survey(space, name, questions)
    return unless component_available?(:surveys)

    component = upsert_component(space, "surveys", name)
    return if Decidim::Surveys::Survey.where(component:).any?

    questionnaire = Decidim::Forms::Questionnaire.new(
      title: name, description: para("Help shape this process.", "Bu sürece yön verin."),
      tos: para("Your responses are used only for this process.", "Yanıtlarınız yalnızca bu süreç için kullanılır.")
    )
    Decidim::Surveys::Survey.create!(component:, questionnaire:, allow_responses: true, published_at: Time.current)
    questions.each_with_index do |(body, type), i|
      Decidim::Forms::Question.create!(questionnaire:, body:, question_type: type, position: i, mandatory: i.zero?)
    end
  end
end
